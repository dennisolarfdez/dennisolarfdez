// Este main.js muestra supply y balances correctamente para cTokens con 18 decimales (como los de tu contrato actual).
// Corrige la conversión para totalSupply, userSupply y underlying, tanto para la tabla de pool como la personal.
// Si añades un nuevo asset con decimales distintos, ajusta el mapeo en cTokenDecimals.

const C_TOKEN_ABI   = window.C_TOKEN_ABI;
const MASTER_ABI    = window.MASTER_ABI;
const MIN_ERC20_ABI = window.MIN_ERC20_ABI;

let provider, signer, userAddress, NETWORKS_DATA, ACTIVE;

const btnConnect       = document.getElementById("btnConnect");
const btnEnter         = document.getElementById("btnEnter");
const walletAddrSpan   = document.getElementById("walletAddr");
const networkTag       = document.getElementById("networkTag");
const networkSelect    = document.getElementById("networkSelect");
const marketsBody      = document.getElementById("marketsBody");
const hfValue          = document.getElementById("hfValue");
const liqUSDSpan       = document.getElementById("liqUSD");
const borUSDSpan       = document.getElementById("borUSD");
const actionCTokenSel  = document.getElementById("actionCToken");
const actionTypeSel    = document.getElementById("actionType");
const actionAmountInput= document.getElementById("actionAmount");
const btnDo            = document.getElementById("btnDo");
const txStatus         = document.getElementById("txStatus");

const ICON_MAP = { ASTR: "icons/astr.svg", USDC: "icons/usdc.svg" };

function formatNumber(n, dp=2) {
  return Number(n).toLocaleString('en-US', {minimumFractionDigits:0, maximumFractionDigits:dp});
}

function formatBn(big, decimals, dp=2) {
  try {
    return formatNumber(Number(big.toString()) / Math.pow(10, decimals), dp);
  } catch { return "0"; }
}

function ratePerBlockToAPY(rateMantissa, blocksPerYear) {
  const r = Number(rateMantissa)/1e18;
  if (r <= 0) return 0;
  if (r > 0.5) return r * blocksPerYear * 100;
  return (Math.pow(1+r, blocksPerYear)-1)*100;
}

async function initNetworks() {
  NETWORKS_DATA = await window.loadNetworks();
  const enabled = window.listEnabledNetworks(NETWORKS_DATA);
  networkSelect.innerHTML = "";
  for (const n of enabled) {
    const opt = document.createElement("option");
    opt.value = n.slug;
    opt.textContent = n.label;
    networkSelect.appendChild(opt);
  }
}

async function detectActiveNetwork() {
  const chainIdHex = await provider.send("eth_chainId", []);
  ACTIVE = window.getActiveNetworkByChainId(NETWORKS_DATA, chainIdHex);
  if (!ACTIVE) {
    networkTag.textContent = "Red no soportada";
    txStatus.textContent = "Cambia a una red soportada.";
    return false;
  }
  networkTag.textContent = "Red: " + ACTIVE.label;
  networkSelect.value = ACTIVE.slug;
  return true;
}

btnConnect.onclick = async () => {
  if (!window.ethereum) { alert("Instala MetaMask"); return; }
  provider = new ethers.BrowserProvider(window.ethereum);
  await initNetworks();
  await provider.send("eth_requestAccounts", []);
  signer = await provider.getSigner();
  userAddress = await signer.getAddress();
  walletAddrSpan.textContent = userAddress;
  const ok = await detectActiveNetwork();
  if (ok) {
    fillActionSelect();
    await refreshAll();
  }
};

networkSelect.onchange = async (e) => {
  const slug = e.target.value;
  const target = window.getNetworkBySlug(NETWORKS_DATA, slug);
  if (!target) return;
  try {
    await window.ethereum.request({
      method:'wallet_switchEthereumChain',
      params:[{ chainId: target.chainId }]
    });
    const ok = await detectActiveNetwork();
    if (ok) {
      fillActionSelect();
      await refreshAll();
    }
  } catch (err) {
    txStatus.textContent = "No se pudo cambiar de red";
  }
};

btnEnter.onclick = async () => {
  if (!signer || !ACTIVE) { alert("Conecta wallet y red"); return; }
  try {
    const master = new ethers.Contract(ACTIVE.master, MASTER_ABI, signer);
    txStatus.textContent = "enterMarkets...";
    const tx = await master.enterMarkets(ACTIVE.cTokens.map(m=>m.address));
    await tx.wait();
    txStatus.textContent = "enterMarkets ok";
    await refreshAll();
  } catch (e) {
    txStatus.textContent = "Error enterMarkets";
  }
};

function fillActionSelect() {
  actionCTokenSel.innerHTML = "";
  for (const m of ACTIVE.cTokens) {
    const opt = document.createElement("option");
    const uSym = m.underlyingSymbol || m.symbol.replace(/^c/,"");
    opt.value = m.address;
    opt.textContent = `${uSym} (${m.symbol})`;
    actionCTokenSel.appendChild(opt);
  }
}

async function refreshAll() {
  marketsBody.innerHTML = "";
  const blocksPerYear = ACTIVE.blocksPerYear || 15768000;
  for (const m of ACTIVE.cTokens) {
    try {
      const c = new ethers.Contract(m.address, C_TOKEN_ABI, provider);

      // Usa los decimales correctos de cada asset (cToken contract decimals es 18 en tu deploy)
      const cTokenDecimals = 18; // tu deploy (V_cERC20_ExtendedInterest), siempre 18 decimales
      const underlyingDecimals = m.underlyingDecimals || 18; // ajusta si tienes underlying con decimales distintos

      const [
        totalSupplyBig, totalBorrowsBig,
        userCTokensBig, userBorrowsBig,
        rates, exchRateRaw
      ] = await Promise.all([
        c.totalSupply(),
        c.totalBorrows(),
        userAddress ? c.balanceOf(userAddress) : 0n,
        userAddress ? c.borrowBalance(userAddress) : 0n,
        c.peekRates(),
        c.exchangeRateStored()
      ]);
      const totalSupply = Number(totalSupplyBig.toString());
      const totalBorrows = Number(totalBorrowsBig.toString());
      const userCTokens = Number(userCTokensBig.toString());
      const userBorrows = Number(userBorrowsBig.toString());
      const exchangeRate = exchRateRaw ? Number(exchRateRaw.toString()) : 1e18;

      // Totales del pool
      const totalSupplyFmtC = (totalSupply / Math.pow(10, cTokenDecimals)).toLocaleString('en-US', {maximumFractionDigits: 2});
      const totalSupplyUnderlying = totalSupply * exchangeRate / (Math.pow(10, cTokenDecimals) * 1e18);
      const totalSupplyFmtUnderlying = (totalSupplyUnderlying).toLocaleString('en-US', {maximumFractionDigits: 2});

      const totalBorrowFmt = (totalBorrows / Math.pow(10, underlyingDecimals)).toLocaleString('en-US', {maximumFractionDigits: 2});

      // Saldos personales
      const userSupplyFmtC = (userCTokens / Math.pow(10, cTokenDecimals)).toLocaleString('en-US', {maximumFractionDigits: 4});
      const userSupplyUnderlying = userCTokens * exchangeRate / (Math.pow(10, cTokenDecimals) * 1e18);
      const userSupplyFmtUnderlying = (userSupplyUnderlying).toLocaleString('en-US', {maximumFractionDigits: 4});
      const userDebtFmtUnderlying = (userBorrows / Math.pow(10, underlyingDecimals)).toLocaleString('en-US', {maximumFractionDigits: 4});

      // APY/Util
      const supplyAPY = rates && rates[1] ? ratePerBlockToAPY(rates[1], blocksPerYear) : 0;
      const borrowAPY = rates && rates[0] ? ratePerBlockToAPY(rates[0], blocksPerYear) : 0;
      const utilPct   = rates && rates[2] ? (Number(rates[2].toString())/1e18*100).toFixed(1) : "0.0";

      const uSym = m.underlyingSymbol || m.symbol.replace(/^c/,"");
      const icon = m.icon || ICON_MAP[uSym] || "icons/unknown.svg";

      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td class="assetCell">
          <img src="${icon}" alt="${uSym}" style="width:22px;height:22px;border-radius:50%;margin-right:6px;vertical-align:middle;" onerror="this.src='icons/unknown.svg';"/>
          <div style="display:inline-block;">
            <strong>${uSym}</strong><br/>
            <span class="muted">${m.symbol}</span>
          </div>
        </td>
        <td>
          ${totalSupplyFmtC} <span class="muted">${m.symbol}</span><br>
          <span style="font-size:11px;color:#8fa2b7;">(~${totalSupplyFmtUnderlying} ${uSym})</span>
        </td>
        <td><span style="font-weight:bold;color:#2d6cdf;">${supplyAPY.toFixed(2)}%</span></td>
        <td>${totalBorrowFmt}</td>
        <td><span style="font-weight:bold;color:#ffb347;">${borrowAPY.toFixed(2)}%</span></td>
        <td>
          <span style="display:inline-block;">
            Supply: <span style="color:#64fa;">${userSupplyFmtUnderlying} ${uSym}</span><br/>
            <span class="muted">${userSupplyFmtC} ${m.symbol}</span><br/>
            Debt: ${userDebtFmtUnderlying} ${uSym}<br/>
            Util: <span style="font-weight:bold;color:#5ed0a4;">${utilPct}%</span>
          </span>
        </td>
      `;
      marketsBody.appendChild(tr);
    } catch (e) {
      console.error(`Error en el mercado ${m.symbol}:`, e);
      const tr = document.createElement("tr");
      tr.innerHTML = `<td>${m.symbol}</td><td colspan="5">Error</td>`;
      marketsBody.appendChild(tr);
    }
  }
  if (userAddress) {
    try {
      const master = new ethers.Contract(ACTIVE.master, MASTER_ABI, provider);
      const res = await master.getAccountLiquidity(userAddress);
      const ld = res.ld ? res.ld : res;
      const borrowPower = Number(ld.liquidationUSD)/1e18;
      const borrowed    = Number(ld.borrowUSD)/1e18;
      const hf = ld.borrowUSD === 0n ? Infinity : borrowPower / borrowed;
      liqUSDSpan.textContent = borrowPower.toFixed(2);
      borUSDSpan.textContent = borrowed.toFixed(2);
      hfValue.textContent = hf === Infinity ? "∞" : hf.toFixed(2);
    } catch {}
  }
}

btnDo.onclick = async () => {
  if (!signer || !ACTIVE) { alert("Conecta wallet"); return; }
  const cAddr = actionCTokenSel.value;
  const action = actionTypeSel.value;
  const amountStr = actionAmountInput.value.trim();
  if (!amountStr) { alert("Ingresa monto"); return; }
  const m = ACTIVE.cTokens.find(x => x.address === cAddr);
  const cTokenDecimals = 18; // tu deploy
  const decimals = action === "redeem" ? cTokenDecimals : m.underlyingDecimals;
  const raw = parseToRaw(amountStr, decimals);
  if (raw === 0n) { alert("Monto inválido"); return; }
  const c = new ethers.Contract(cAddr, C_TOKEN_ABI, signer);
  try {
    if (action === "mint") {
      if (!m.skipAllowance) {
        await ensureAllowance(m.underlying, cAddr, raw);
      }
      txStatus.textContent = "Mint...";
      const tx = await c.mint(raw); await tx.wait(); txStatus.textContent = "Mint ok";
    } else if (action === "redeem") {
      txStatus.textContent = "Redeem...";
      const tx = await c.redeem(raw); await tx.wait(); txStatus.textContent = "Redeem ok";
    } else if (action === "borrow") {
      txStatus.textContent = "Borrow...";
      const tx = await c.borrow(raw); await tx.wait(); txStatus.textContent = "Borrow ok";
    } else if (action === "repay") {
      if (!m.skipAllowance) {
        await ensureAllowance(m.underlying, cAddr, raw);
      }
      txStatus.textContent = "Repay...";
      const tx = await c.repay(raw); await tx.wait(); txStatus.textContent = "Repay ok";
    } else {
      alert("Acción no soportada");
    }
    await refreshAll();
  } catch (e) {
    txStatus.textContent = "Error: " + (e.shortMessage || e.message);
  }
};

function parseToRaw(amountStr, decimals) {
  const parts = amountStr.split(".");
  let whole = parts[0] || "0";
  let frac = parts[1] || "";
  if (!/^\d+$/.test(whole) || (frac && !/^\d+$/.test(frac))) return 0n;
  if (frac.length > decimals) frac = frac.slice(0,decimals);
  while (frac.length < decimals) frac += "0";
  return BigInt(whole + frac);
}

async function ensureAllowance(underlying, spender, neededRaw) {
  const erc = new ethers.Contract(underlying, MIN_ERC20_ABI, signer);
  try {
    const current = await erc.allowance(userAddress, spender);
    if (current >= neededRaw) return;
    txStatus.textContent = "Approve...";
    const tx = await erc.approve(spender, neededRaw);
    await tx.wait();
    txStatus.textContent = "Approve ok";
  } catch(e) {
    console.error("Approve error", e);
    throw e;
  }
}
