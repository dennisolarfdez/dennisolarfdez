// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

/**
 * @title V_VibeToken
 * @notice Token de gobernanza / recompensas con control total y emisión limitada.
 *         - Emisión: sólo EMISSION_MANAGER_ROLE (normalmente el Master o un EmissionsController).
 *         - Burn: roles BURNER_ROLE o usuario (self-burn).
 *         - Pausa de transferencias para emergencia (PAUSER_ROLE).
 *         - Blacklist opcional (DEFAULT_ADMIN_ROLE).
 *         - Rescue de tokens atrapados (RESCUER_ROLE).
 */
contract V_VibeToken is ERC20, ERC20Permit, AccessControl {

    // Roles
    bytes32 public constant EMISSION_MANAGER_ROLE = keccak256("EMISSION_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE           = keccak256("PAUSER_ROLE");
    bytes32 public constant RESCUER_ROLE          = keccak256("RESCUER_ROLE");
    bytes32 public constant BURNER_ROLE           = keccak256("BURNER_ROLE");

    // Supply cap
    uint256 public immutable maxSupply;

    // Pausa de transferencias
    bool public transfersPaused;

    // Blacklist opcional (para entornos controlados; puedes eliminar si no la quieres)
    mapping(address => bool) public blacklist;
    event TransfersPaused(bool paused);
    event Blacklisted(address indexed account, bool blacklisted);
    event EmissionMint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    event BurnFrom(address indexed operator, address indexed from, uint256 amount);

    modifier notPaused() {
        require(!transfersPaused, "transfers paused");
        _;
    }
    modifier notBlacklisted(address from, address to) {
        require(!blacklist[from] && !blacklist[to], "blacklisted");
        _;
    }

    constructor(
        uint256 _maxSupply,
        address admin,
        address emissionManager
    )
        ERC20("Vibe Governance Token", "VIBE")
        ERC20Permit("Vibe Governance Token")
    {
        require(_maxSupply > 0, "maxSupply=0");
        maxSupply = _maxSupply;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(EMISSION_MANAGER_ROLE, emissionManager);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(RESCUER_ROLE, admin);
        _grantRole(BURNER_ROLE, admin);
    }

    // ----- Admin / Control -----
    function pauseTransfers(bool paused) external onlyRole(PAUSER_ROLE) {
        transfersPaused = paused;
        emit TransfersPaused(paused);
    }

    function setBlacklist(address account, bool value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blacklist[account] = value;
        emit Blacklisted(account, value);
    }

    // ----- Emisión -----
    function mintEmission(address to, uint256 amount) external onlyRole(EMISSION_MANAGER_ROLE) {
        require(amount > 0, "amount=0");
        require(totalSupply() + amount <= maxSupply, "cap exceeded");
        _mint(to, amount);
        emit EmissionMint(to, amount);
    }

    // ----- Burn -----
    // Self-burn (usuario se quema su propio balance)
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    // Burn controlado (ej. para treasury / penalizaciones)
    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        emit BurnFrom(msg.sender, from, amount);
    }

    // ----- Transfer override con controles -----
    function _update(address from, address to, uint256 value)
        internal
        override
        notPaused
        notBlacklisted(from, to)
    {
        super._update(from, to, value);
    }

    // ----- Rescue tokens externos (no VIBE) -----
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(RESCUER_ROLE) {
        require(to != address(0), "to=0");
        require(token != address(this), "no self rescue");
        (bool ok, bytes memory data) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (data.length == 0 || abi.decode(data,(bool))), "rescue fail");
    }
}