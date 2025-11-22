// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IV_MasterEnhanced.sol";
import "../interfaces/IVibePriceOracle.sol";
import "../libraries/SafeTransferLib.sol";

/// @dev Interfaces mínimas internas (mantener, no romper compat).
interface IERC20Basic {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

interface IInterestRateModel {
    function isInterestRateModel() external pure returns (bool);
    function getBorrowRate(uint cash, uint borrows, uint reserves) external view returns (uint);
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) external view returns (uint);
}

/// @title cToken con interés compuesto y soporte para recompensas + caps + pausas.
/// @notice Parche aditivo: mantiene toda la lógica original e incorpora:
///         - Enforcement de supplyCap y borrowCap.
///         - Uso de canMint/canBorrow del Master antes de ejecutar.
///         - Hooks de recompensas: updateMarketRewards y distributeSupplier / distributeBorrower.
///         - Distribución también en liquidaciones.
///         - No cambiamos orden de variables de storage existentes.
contract V_cERC20_ExtendedInterest {
    // ======================================================
    // Identidad
    // ======================================================
    string public name;
    string public symbol;
    uint8 public decimals; // cToken siempre 18

    // ======================================================
    // Componentes
    // ======================================================
    address public immutable underlying;
    IV_MasterEnhanced public immutable comptroller;
    address public guardian;

    // ======================================================
    // Supply (cTokens)
    // ======================================================
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ======================================================
    // Interés (global)
    // ======================================================
    uint256 public accrualBlockNumber;
    uint256 public borrowIndex;          // 1e18 inicial
    uint256 public totalBorrows;         // underlying raw
    uint256 public totalReserves;        // underlying raw
    uint256 public reserveFactorMantissa;
    IInterestRateModel public interestRateModel;

    // Interés (por cuenta)
    mapping(address => uint256) public borrowPrincipal;
    mapping(address => uint256) public accountBorrowIndex;

    // Exchange rate inicial
    uint256 public exchangeRateInitialMantissa = 1e18;

    // Acumulador remainder para reservas
    uint256 public reserveRemainder; // escala 1e18

    // Reentrancy guard
    uint8 private _status;
    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    // Pausa de transferencias
    bool public transfersPaused;

    // ======================================================
    // Eventos (originales)
    // ======================================================
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Mint(address indexed minter, uint256 underlyingAmount, uint256 cTokensMinted);
    event Redeem(address indexed redeemer, uint256 underlyingAmount, uint256 cTokensBurned);
    event Borrow(address indexed borrower, uint256 amount);
    event Repay(address indexed payer, address indexed borrower, uint256 amount);
    event LiquidateBorrow(address indexed liquidator, address indexed borrower, uint256 repayAmount, address cTokenCollateral, uint256 seizeTokens);
    event GuardianSet(address indexed guardian);
    event AccrueInterest(uint256 interestAccumulated, uint256 borrowIndexNew, uint256 totalBorrowsNew, uint256 totalReservesNew);
    event NewReserveFactor(uint256 oldFactor, uint256 newFactor);
    event NewInterestRateModel(address oldModel, address newModel);
    event ReservesAdded(address indexed from, uint256 amount, uint256 totalReservesNew);
    event ReservesReduced(address indexed to, uint256 amount, uint256 totalReservesNew);
    event TransfersPaused(bool paused);

    // ======================================================
    // Errores (nuevos opcionales)
    // ======================================================
    error Reentrancy();
    error NotGuardian();
    error TransfersPausedErr();
    error InsufficientBalance();
    error AllowanceExceeded();
    error BadMintAmount();
    error BadRedeemAmount();
    error BorrowZero();
    error RepayZero();
    error NoDebt();
    error CollateralInsufficient();
    error BorrowCapExceeded();
    error SupplyCapExceeded();
    error MarketPaused();
    error MintNotAllowed();
    error BorrowNotAllowed();
    error LiquidationSelf();
    error InvalidIRM();
    error RateTooHigh();
    error UnderlyingTransferFailed();
    error BadAddress(); // <- agregado para revert BadAddress()

    // ======================================================
    // Modificadores
    // ======================================================
    modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    // ======================================================
    // Constructor
    // ======================================================
    constructor(
        string memory _n,
        string memory _s,
        address _underlying,
        address _comptroller,
        address _guardian,
        address _irm,
        uint256 _reserveFactorMantissa
    ) {
        name = _n;
        symbol = _s;
        decimals = 18;

        underlying = _underlying;
        comptroller = IV_MasterEnhanced(_comptroller);
        require(comptroller.isComptroller(), "invalid comptroller");

        guardian = _guardian;
        emit GuardianSet(_guardian);

        IInterestRateModel irm = IInterestRateModel(_irm);
        if (!irm.isInterestRateModel()) revert InvalidIRM();
        interestRateModel = irm;
        reserveFactorMantissa = _reserveFactorMantissa;

        borrowIndex = 1e18;
        accrualBlockNumber = block.number;
        _status = _NOT_ENTERED;
    }

    // ======================================================
    // Compatibilidad / Underlying
    // ======================================================
    function underlyingAddress() external view returns (address) { return underlying; }
    function underlyingDecimals() public view returns (uint8) { return IERC20Basic(underlying).decimals(); }

    // Normalización a 18 para exchange rate
    function _toNormalized(uint256 raw) internal view returns (uint256) {
        uint8 ud = underlyingDecimals();
        if (ud == 18) return raw;
        if (ud < 18) return raw * (10 ** (18 - ud));
        return raw / (10 ** (ud - 18));
    }
    function _fromNormalized(uint256 norm) internal view returns (uint256) {
        uint8 ud = underlyingDecimals();
        if (ud == 18) return norm;
        if (ud < 18) return norm / (10 ** (18 - ud));
        return norm * (10 ** (ud - 18));
    }

    // ======================================================
    // Admin
    // ======================================================
    function setGuardian(address g) external onlyGuardian {
        guardian = g;
        emit GuardianSet(g);
    }
    function setReserveFactor(uint256 newFactor) external onlyGuardian {
        require(newFactor <= 0.25e18, "too high");
        emit NewReserveFactor(reserveFactorMantissa, newFactor);
        reserveFactorMantissa = newFactor;
    }
    function setInterestRateModel(address newModel) external onlyGuardian {
        IInterestRateModel irm = IInterestRateModel(newModel);
        if (!irm.isInterestRateModel()) revert InvalidIRM();
        emit NewInterestRateModel(address(interestRateModel), newModel);
        interestRateModel = irm;
    }
    function setTransfersPaused(bool paused) external onlyGuardian {
        transfersPaused = paused;
        emit TransfersPaused(paused);
    }

    // ======================================================
    // Intereses
    // ======================================================
    function accrueInterest() public {
        uint256 currentBlock = block.number;
        uint256 delta = currentBlock - accrualBlockNumber;
        if (delta == 0) return;

        uint256 cash = IERC20Basic(underlying).balanceOf(address(this));
        uint256 borrows = totalBorrows;
        uint256 reserves = totalReserves;

        uint256 borrowRate = interestRateModel.getBorrowRate(cash, borrows, reserves);
        if (borrowRate > 5e13) revert RateTooHigh();

        uint256 interestAccumulated = (borrowRate * delta * borrows) / 1e18;
        uint256 totalBorrowsNew = borrows + interestAccumulated;

        uint256 product = interestAccumulated * reserveFactorMantissa; // 1e36
        uint256 reservesAdded = product / 1e18;
        uint256 newRemainder = reserveRemainder + (product % 1e18);

        if (newRemainder >= 1e18) {
            uint256 extra = newRemainder / 1e18;
            reservesAdded += extra;
            newRemainder = newRemainder % 1e18;
        }

        uint256 totalReservesNew = totalReserves + reservesAdded;
        uint256 borrowIndexNew = borrowIndex + ((borrowRate * delta * borrowIndex) / 1e18);

        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;
        borrowIndex = borrowIndexNew;
        accrualBlockNumber = currentBlock;
        reserveRemainder = newRemainder;

        emit AccrueInterest(interestAccumulated, borrowIndexNew, totalBorrowsNew, totalReservesNew);

        comptroller.updateMarketRewards(address(this));
    }

    // ======================================================
    // Exchange Rate
    // ======================================================
    function exchangeRateStored() public view returns (uint256) {
        if (totalSupply == 0) return exchangeRateInitialMantissa;
        uint256 cashNorm = _toNormalized(IERC20Basic(underlying).balanceOf(address(this)));
        uint256 borNorm  = _toNormalized(totalBorrows);
        uint256 resNorm  = _toNormalized(totalReserves);
        uint256 numerator = cashNorm + borNorm - resNorm;
        return (numerator * 1e18) / totalSupply;
    }
    function exchangeRateCurrent() external returns (uint256) {
        accrueInterest();
        return exchangeRateStored();
    }

    // ======================================================
    // ERC20-like
    // ======================================================
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (transfersPaused) revert TransfersPausedErr();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        if (!comptroller.canRedeem(msg.sender, address(this), amount)) revert CollateralInsufficient();

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);

        comptroller.distributeSupplier(msg.sender, address(this), balanceOf[msg.sender]);
        comptroller.distributeSupplier(to, address(this), balanceOf[to]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (transfersPaused) revert TransfersPausedErr();
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert AllowanceExceeded();
        allowance[from][msg.sender] = allowed - amount;

        if (balanceOf[from] < amount) revert InsufficientBalance();
        if (!comptroller.canRedeem(from, address(this), amount)) revert CollateralInsufficient();

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);

        comptroller.distributeSupplier(from, address(this), balanceOf[from]);
        comptroller.distributeSupplier(to, address(this), balanceOf[to]);
        return true;
    }

    // ======================================================
    // Mint
    // ======================================================
    function mint(uint256 amount) external nonReentrant {
        accrueInterest();
        if (amount == 0) revert BadMintAmount();
        if (!comptroller.canMint(msg.sender, address(this), amount)) revert MintNotAllowed();

        uint256 cap = comptroller.marketSupplyCaps(address(this));
        if (cap != 0) {
            uint256 cash = IERC20Basic(underlying).balanceOf(address(this));
            uint256 underlyingAfter = cash + amount + totalBorrows - totalReserves;
            if (underlyingAfter > cap) revert SupplyCapExceeded();
        }

        SafeTransferLib.safeTransferFrom(underlying, msg.sender, address(this), amount);

        uint256 exRate = exchangeRateStored();
        uint256 cTokens = (_toNormalized(amount) * 1e18) / exRate;
        totalSupply += cTokens;
        balanceOf[msg.sender] += cTokens;

        emit Mint(msg.sender, amount, cTokens);
        emit Transfer(address(0), msg.sender, cTokens);

        comptroller.distributeSupplier(msg.sender, address(this), balanceOf[msg.sender]);
    }

    // ======================================================
    // Redeem
    // ======================================================
    function redeem(uint256 cTokenAmount) external nonReentrant {
        accrueInterest();
        if (cTokenAmount == 0 || balanceOf[msg.sender] < cTokenAmount) revert BadRedeemAmount();
        if (!comptroller.canRedeem(msg.sender, address(this), cTokenAmount)) revert CollateralInsufficient();

        uint256 exRate = exchangeRateStored();
        uint256 underlyingNorm = (cTokenAmount * exRate) / 1e18;
        uint256 underlyingRaw = _fromNormalized(underlyingNorm);

        balanceOf[msg.sender] -= cTokenAmount;
        totalSupply -= cTokenAmount;

        SafeTransferLib.safeTransfer(underlying, msg.sender, underlyingRaw);

        emit Redeem(msg.sender, underlyingRaw, cTokenAmount);
        emit Transfer(msg.sender, address(0), cTokenAmount);

        comptroller.distributeSupplier(msg.sender, address(this), balanceOf[msg.sender]);
    }

    // ======================================================
    // Borrow / Repay
    // ======================================================
    function _currentBorrowBalance(address account) internal view returns (uint256) {
        uint256 p = borrowPrincipal[account];
        if (p == 0) return 0;
        uint256 idx = accountBorrowIndex[account];
        if (idx == 0) return 0;
        return (p * borrowIndex) / idx;
    }
    function borrowBalance(address account) external view returns (uint256) {
        return _currentBorrowBalance(account);
    }

    function borrow(uint256 amount) external nonReentrant {
        accrueInterest();
        if (amount == 0) revert BorrowZero();
        if (!comptroller.canBorrow(msg.sender, address(this), amount)) revert BorrowNotAllowed();

        uint256 bCap = comptroller.marketBorrowCaps(address(this));
        if (bCap != 0 && totalBorrows + amount > bCap) revert BorrowCapExceeded();

        uint256 prev = _currentBorrowBalance(msg.sender);
        uint256 newBal = prev + amount;
        borrowPrincipal[msg.sender] = (newBal * 1e18) / borrowIndex;
        accountBorrowIndex[msg.sender] = borrowIndex;
        totalBorrows += amount;

        SafeTransferLib.safeTransfer(underlying, msg.sender, amount);
        emit Borrow(msg.sender, amount);

        comptroller.distributeBorrower(msg.sender, address(this), _currentBorrowBalance(msg.sender));
    }

    function repay(uint256 amount) external nonReentrant {
        accrueInterest();
        if (amount == 0) revert RepayZero();
        uint256 userBorrow = _currentBorrowBalance(msg.sender);
        if (userBorrow == 0) revert NoDebt();

        SafeTransferLib.safeTransferFrom(underlying, msg.sender, address(this), amount);
        uint256 repayFinal = amount >= userBorrow ? userBorrow : amount;
        uint256 newBorrow = userBorrow - repayFinal;

        if (newBorrow == 0) {
            borrowPrincipal[msg.sender] = 0;
            accountBorrowIndex[msg.sender] = borrowIndex;
        } else {
            borrowPrincipal[msg.sender] = (newBorrow * 1e18) / borrowIndex;
            accountBorrowIndex[msg.sender] = borrowIndex;
        }
        totalBorrows -= repayFinal;

        emit Repay(msg.sender, msg.sender, repayFinal);

        comptroller.distributeBorrower(msg.sender, address(this), _currentBorrowBalance(msg.sender));
    }

    // ======================================================
    // Liquidaciones
    // ======================================================
    function liquidateBorrow(address borrower, uint256 repayAmount, address cTokenCollateral) external nonReentrant {
        accrueInterest();
        if (cTokenCollateral != address(this)) {
            V_cERC20_ExtendedInterest(cTokenCollateral).accrueInterest();
        }
        if (borrower == msg.sender) revert LiquidationSelf();

        uint256 borrowerDebtPrev = _currentBorrowBalance(borrower);
        if (borrowerDebtPrev == 0) revert NoDebt();

        if (!comptroller.seizeAllowed(borrower, msg.sender, cTokenCollateral, address(this), 0))
            revert CollateralInsufficient();

        uint256 cf = comptroller.closeFactorMantissa();
        uint256 maxRepay = (borrowerDebtPrev * cf + 1e18 - 1) / 1e18;
        if (maxRepay > borrowerDebtPrev) maxRepay = borrowerDebtPrev;

        if (repayAmount > maxRepay) repayAmount = maxRepay;
        if (repayAmount > borrowerDebtPrev) repayAmount = borrowerDebtPrev;
        if (repayAmount == 0) revert RepayZero();

        uint256 seizeCTokens = _computeSeizeCTokens(cTokenCollateral, repayAmount);
        require(seizeCTokens > 0, "seize zero");

        SafeTransferLib.safeTransferFrom(underlying, msg.sender, address(this), repayAmount);

        if (cTokenCollateral == address(this)) {
            require(balanceOf[borrower] >= seizeCTokens, "insufficient collateral tokens");
            balanceOf[borrower] -= seizeCTokens;
            balanceOf[msg.sender] += seizeCTokens;
            emit Transfer(borrower, msg.sender, seizeCTokens);
            comptroller.distributeSupplier(borrower, address(this), balanceOf[borrower]);
            comptroller.distributeSupplier(msg.sender, address(this), balanceOf[msg.sender]);
        } else {
            V_cERC20_ExtendedInterest(cTokenCollateral).seize(msg.sender, borrower, seizeCTokens);
        }

        uint256 newBorrow = borrowerDebtPrev - repayAmount;
        if (newBorrow == 0) {
            borrowPrincipal[borrower] = 0;
            accountBorrowIndex[borrower] = borrowIndex;
        } else {
            borrowPrincipal[borrower] = (newBorrow * 1e18) / borrowIndex;
            accountBorrowIndex[borrower] = borrowIndex;
        }
        totalBorrows -= repayAmount;

        emit LiquidateBorrow(msg.sender, borrower, repayAmount, cTokenCollateral, seizeCTokens);
        comptroller.distributeBorrower(borrower, address(this), _currentBorrowBalance(borrower));
    }

    function seize(address liquidator, address borrower, uint256 seizeTokens) external nonReentrant {
        if (!comptroller.seizeAllowed(borrower, liquidator, address(this), msg.sender, seizeTokens))
            revert CollateralInsufficient();
        require(balanceOf[borrower] >= seizeTokens, "insufficient collateral tokens");
        balanceOf[borrower] -= seizeTokens;
        balanceOf[liquidator] += seizeTokens;
        emit Transfer(borrower, liquidator, seizeTokens);
        comptroller.distributeSupplier(borrower, address(this), balanceOf[borrower]);
        comptroller.distributeSupplier(liquidator, address(this), balanceOf[liquidator]);
    }

    // ======================================================
    // Reservas
    // ======================================================
    function addReserves(uint256 amount) external onlyGuardian {
        if (amount == 0) revert BadMintAmount();
        accrueInterest();
        SafeTransferLib.safeTransferFrom(underlying, msg.sender, address(this), amount);
        totalReserves += amount;
        emit ReservesAdded(msg.sender, amount, totalReserves);
    }

    function reduceReserves(address to, uint256 amount) external onlyGuardian {
        if (to == address(0)) revert BadAddress();
        if (amount == 0) revert BadRedeemAmount();
        accrueInterest();
        if (amount > totalReserves) revert CollateralInsufficient();
        uint256 cash = IERC20Basic(underlying).balanceOf(address(this));
        if (cash < amount) revert UnderlyingTransferFailed();
        totalReserves -= amount;
        SafeTransferLib.safeTransfer(underlying, to, amount);
        emit ReservesReduced(to, amount, totalReserves);
    }

    // ======================================================
    // Preview / Cálculos liquidación
    // ======================================================
    function previewSeizeTokens(address cTokenCollateral, uint256 repayAmount) external view returns (uint256) {
        return _computeSeizeCTokens(cTokenCollateral, repayAmount);
    }

    function _computeSeizeCTokens(address cTokenCollateral, uint256 repayAmount) internal view returns (uint256) {
        IVibePriceOracle o = IVibePriceOracle(comptroller.oracle());
        uint256 priceBorrowed = o.getUnderlyingPrice(address(this));
        if (priceBorrowed == 0) return 0;
        uint256 priceCollateral = o.getUnderlyingPrice(cTokenCollateral);
        if (priceCollateral == 0) return 0;

        uint8 decBorrow = underlyingDecimals();
        uint256 repayUSD = (repayAmount * priceBorrowed) / (10 ** decBorrow);

        uint256 incentive = comptroller.liquidationIncentiveMantissa();
        if (incentive < 1e18) return 0;
        uint256 seizeUSD = (repayUSD * incentive) / 1e18;

        address uCol = V_cERC20_ExtendedInterest(cTokenCollateral).underlyingAddress();
        uint8 decCol = IERC20Basic(uCol).decimals();
        uint256 seizeUnderlyingRaw = (seizeUSD * (10 ** decCol)) / priceCollateral;

        uint256 normalized;
        if (decCol < 18) normalized = seizeUnderlyingRaw * (10 ** (18 - decCol));
        else if (decCol > 18) normalized = seizeUnderlyingRaw / (10 ** (decCol - 18));
        else normalized = seizeUnderlyingRaw;

        uint256 exRateCol = V_cERC20_ExtendedInterest(cTokenCollateral).exchangeRateStored();
        return (normalized * 1e18) / exRateCol;
    }

    // ======================================================
    // Rewards preview (informativo)
    // ======================================================
    function peekRates()
        external
        view
        returns (uint borrowRatePerBlock, uint supplyRatePerBlock, uint utilization)
    {
        uint cash = IERC20Basic(underlying).balanceOf(address(this));
        uint borrows = totalBorrows;
        uint reserves = totalReserves;
        if (borrows == 0 || cash + borrows <= reserves) {
            return (interestRateModel.getBorrowRate(cash, borrows, reserves), 0, 0);
        }
        utilization = borrows * 1e18 / (cash + borrows - reserves);
        borrowRatePerBlock = interestRateModel.getBorrowRate(cash, borrows, reserves);
        supplyRatePerBlock = interestRateModel.getSupplyRate(cash, borrows, reserves, reserveFactorMantissa);
    }
}