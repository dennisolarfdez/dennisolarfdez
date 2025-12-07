let provider, signer, userAddress, NETWORKS_DATA, ACTIVE;
let selectedProvider = null; // Helper esencial para el modal

const getEl = (id) => document.getElementById(id);

// --- UI HELPERS PRO ---
const updateStatus = (connected) => {
  const dot = getEl('statusDot');
  const txt = getEl('connStatus');
  const btn = getEl('btnConnect');
  
  if(connected && userAddress) {
    dot.style.color = "var(--success)";
    txt.textContent = "Online";
    
    // Pro Button Style
    btn.textContent = userAddress.substring(0,6) + "..." + userAddress.substring(38);
    btn.classList.remove('btn-primary');
    btn.classList.add('btn-connected');
    
    // Icono Dropdown
    const arrow = document.createElement("span");
    arrow.textContent = "▼";
    arrow.style.fontSize = "0.7em";
    arrow.style.marginLeft = "6px";
    if (btn.lastChild && btn.lastChild.tagName === 'SPAN') btn.removeChild(btn.lastChild);
    btn.appendChild(arrow);
    
    // Dropdown Data
    getEl('dropdownAddress').textContent = userAddress.substring(0,8) + "..." + userAddress.substring(38);

  } else {
    dot.style.color = "var(--warning)";
    txt.textContent = "Syncing...";
    
    btn.textContent = "Connect Wallet";
    btn.className = "btn-primary";
    btn.style.background = "";
  }
};

// --- INIT APP (OFFLINE + AUTO-CONNECT) ---
document.addEventListener("DOMContentLoaded", initApp);

async function initApp() {
    try {
        NETWORKS_DATA = await window.loadNetworks();
        initNetworkSelector();

        // Carga Read-Only inicial (sin wallet)
        await tryLoadReadOnlyData();

        // Auto-Connect Pro
        if(window.checkAutoConnect) {
            await window.checkAutoConnect(connectWallet);
        }
    } catch(e) { console.log("Init failed", e); }
}

async function tryLoadReadOnlyData() {
    // Si hay un provider inyectado (aunque no conectado), intenta leer la cadena actual
    if(window.ethereum) {
        try {
            const tempProvider = new ethers.BrowserProvider(window.ethereum);
            const chainIdHex = await tempProvider.send("eth_chainId", []);
            const chainIdDecimal = parseInt(chainIdHex, 16);
            ACTIVE = Object.values(NETWORKS_DATA).find(n => (parseInt(n.chainId) === chainIdDecimal) && n.enabled);
            
            if(ACTIVE) {
                provider = tempProvider;
                const sel = getEl("networkSelect");
                if(sel) sel.value = ACTIVE.chainId;
                await loadMarketData();
            }
        } catch(e) {}
    }
}

function initNetworkSelector() {
    const sel = getEl("networkSelect");
    if (!NETWORKS_DATA || !sel) return;
    
    sel.innerHTML = "";
    Object.values(NETWORKS_DATA).forEach(n => {
        if(n.enabled) {
            const opt = document.createElement("option");
            opt.value = n.chainId; 
            opt.textContent = n.label;
            sel.appendChild(opt);
        }
    });

    sel.onchange = async (e) => {
        const targetChainId = e.target.value;
        if(userAddress) {
             await switchNetwork(targetChainId);
        } else {
             ACTIVE = Object.values(NETWORKS_DATA).find(n => n.chainId == targetChainId);
             console.log("Read-mode network changed:", ACTIVE.label);
        }
    };
}

// ===============================================
// ⚡ BRUTAL MODAL LOGIC (VERSIÓN DEFINITIVA) ⚡
// ===============================================

// 1. Renderizado Inteligente & Apertura
function openWalletModal() {
    const modal = getEl('walletModal');
    const list = getEl('walletList');
    if (!modal || !list) return;
    
    // Reset view
    list.style.display = 'grid'; 
    const qrView = getEl('qrView');
    if(qrView) qrView.classList.remove('active');

    list.innerHTML = ''; 
    
    // FIX: Usamos window.WALLET_CONFIG.list (Objeto Nuevo)
    const config = window.WALLET_CONFIG;

    if (config && config.list) {
        config.list.forEach(w => {
            const isInstalled = w.check();
            const isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
            
            // Filtro Mobile-First: Limpieza visual
            if (isMobile && !isInstalled && !w.mobileDeepLink && w.id !== 'walletconnect') return;

            const btn = document.createElement('div');
            btn.className = 'wallet-btn';
            
            // Badges Visuales
            let badgeHtml = '';
            if (isInstalled) badgeHtml = `<span class="wallet-badge installed">Detected</span>`;
            else if (w.id === 'walletconnect') badgeHtml = `<span class="wallet-badge">Scan</span>`;
            
            btn.innerHTML = `
                <div class="wallet-info">
                    ${w.icon}
                    <span>${w.name}</span>
                </div>
                ${badgeHtml}
            `;
            
            btn.onclick = async () => {
                // CASO A: WalletConnect
                if (w.id === 'walletconnect') {
                    showWalletConnectQR();
                    return;
                }

                // CASO B: Wallet Inyectada
                if(isInstalled) {
                    selectedProvider = w.getProvider(); 
                    closeWalletModal();
                    await connectWallet();
                    return;
                }

                // CASO C: Mobile Deep Link
                if(isMobile && w.mobileDeepLink) {
                    window.location.href = w.mobileDeepLink();
                    return;
                }

                // CASO D: Fallback Desktop
                window.open(`https://${w.id}.io`, '_blank');
            };
            list.appendChild(btn);
        });
    }
    
    modal.classList.add('open');
}

// 2. Vista QR (Simulación Brutal)
function showWalletConnectQR() {
    const list = getEl('walletList');
    list.style.display = 'none'; 
    
    let qrView = getEl('qrView');
    if(!qrView) {
        qrView = document.createElement('div');
        qrView.id = 'qrView';
        qrView.className = 'qr-container'; // Usa estilos de style.css
        qrView.style.textAlign = "center";
        
        qrView.innerHTML = `
            <h3 style="margin-top:0; color:#fff;">Scan with Phone</h3>
            <p style="color:var(--text-muted); font-size:0.9rem; margin-bottom:20px;">Use Trust Wallet or MetaMask app.</p>
            
            <div id="qrTarget" style="background:#fff; padding:15px; border-radius:20px; margin:0 auto; width:220px; height:220px; display:flex; align-items:center; justify-content:center;">
                <div style="border:4px solid #f3f3f3; border-top:4px solid var(--accent); border-radius:50%; width:40px; height:40px; animation:spin 1s linear infinite;"></div>
            </div>
            
            <button class="btn-ghost" onclick="backToWalletList()" style="width:100%; margin-top:20px;">Back</button>
            <style>@keyframes spin {0%{transform:rotate(0deg)}100%{transform:rotate(360deg)}}</style>
        `;
        getEl('walletModal').querySelector('.modal-card').appendChild(qrView);
    }
    qrView.style.display = "block";
    qrView.classList.add('active');
    
    // Simular carga del QR real
    setTimeout(() => {
        const t = getEl('qrTarget');
        if(t) t.innerHTML = `<img src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=wc:example-vibe-protocol" style="width:100%; border-radius:10px;">`;
    }, 1000);
}

window.backToWalletList = () => {
    const list = getEl('walletList');
    const qr = getEl('qrView');
    if(list) list.style.display = 'grid';
    if(qr) qr.style.display = 'none';
};

window.closeWalletModal = () => { 
    const modal = getEl('walletModal');
    if(modal) modal.classList.remove('open'); 
};

window.onclick = (e) => {
    const modal = getEl('walletModal');
    if (e.target === modal) closeWalletModal();
    
    const dd = getEl("accountDropdown");
    if (dd && dd.classList.contains('show') && !e.target.closest('#btnConnect')) dd.classList.remove('show');
};

// --- CONNECT & DISCONNECT HANDLERS ---
const btnConnect = getEl("btnConnect");
const accountDropdown = getEl("accountDropdown");

btnConnect.onclick = (e) => {
    e.stopPropagation();
    if(userAddress) {
        if (accountDropdown) accountDropdown.classList.toggle("show");
    } else {
        openWalletModal();
    }
};

getEl("btnCopyAddress").onclick = () => { navigator.clipboard.writeText(userAddress); alert("Copied!"); };
getEl("btnViewExplorer").onclick = () => { if(ACTIVE) window.open(ACTIVE.blockExplorerUrls[0] + "/address/" + userAddress, '_blank'); };

getEl("btnDisconnect").onclick = () => {
    if(window.SessionManager) window.SessionManager.clear();
    userAddress = null;
    signer = null;
    selectedProvider = null;
    updateStatus(false);
    accountDropdown.classList.remove("show");
};

// --- CORE CONNECTION LOGIC ---
async function connectWallet() {
    // 1. Usar provider seleccionado (Trust) o fallback
    const ethProvider = selectedProvider || window.trustwallet || window.ethereum;
    
    if (!ethProvider) { 
        if(/Android|iPhone/i.test(navigator.userAgent)) {
             // Fallback final: Deep link a Trust Wallet si no hay nada
             window.location.href = "https://link.trustwallet.com/open_url?coin_id=60&url=" + encodeURIComponent(window.location.href);
             return;
        }
        alert("Please install Trust Wallet or MetaMask."); return; 
    }
    
    getEl("btnConnect").textContent = "Connecting...";

    try {
        // 'any' permite conectar a redes que Ethers no conoce por defecto (importante para Soneium)
        provider = new ethers.BrowserProvider(ethProvider, "any");
        if(!NETWORKS_DATA) NETWORKS_DATA = await window.loadNetworks();
        
        await provider.send("eth_requestAccounts", []);
        signer = await provider.getSigner();
        userAddress = await signer.getAddress();
        
        if(window.SessionManager) window.SessionManager.save();
        
        const chainIdHex = await provider.send("eth_chainId", []);
        const chainIdDecimal = parseInt(chainIdHex, 16);
        
        ACTIVE = Object.values(NETWORKS_DATA).find(n => (parseInt(n.chainId) === chainIdDecimal) && n.enabled);
        
        const sel = getEl("networkSelect");
        
        // Auto-Switch Logic
        if(!ACTIVE) {
            let targetId = sel ? sel.value : null;
            if(!targetId) {
                const def = Object.values(NETWORKS_DATA).find(n => n.enabled);
                if(def) targetId = def.chainId;
            }
            if(targetId) { await switchNetwork(targetId); return; }
            else { alert("Unsupported Network."); updateStatus(false); return; }
        }
        
        if(sel && ACTIVE) sel.value = ACTIVE.chainId;
        updateStatus(true);
        await loadMarketData();
        
        if(ethProvider.on) {
            ethProvider.on('chainChanged', () => window.location.reload());
            ethProvider.on('accountsChanged', () => window.location.reload());
        }
        
    } catch(e) { 
        console.error(e); 
        updateStatus(false);
        getEl("btnConnect").textContent = "Connect Wallet";
    }
}

async function switchNetwork(targetChainId) {
    const targetNetwork = Object.values(NETWORKS_DATA).find(n => n.chainId == targetChainId);
    if (!targetNetwork) return;
    try {
        await window.ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: "0x" + Number(targetNetwork.chainId).toString(16) }],
        });
    } catch (switchError) {
        if (switchError.code === 4902) {
            try {
                await window.ethereum.request({
                    method: 'wallet_addEthereumChain',
                    params: [{
                        chainId: "0x" + Number(targetNetwork.chainId).toString(16),
                        chainName: targetNetwork.label,
                        rpcUrls: targetNetwork.rpcUrls,
                        blockExplorerUrls: targetNetwork.blockExplorerUrls,
                        nativeCurrency: targetNetwork.nativeCurrency
                    }],
                });
            } catch (e) {}
        }
    }
}

// --- GLOBAL DATA ---
async function loadMarketData() {
    if(!ACTIVE) return;
    
    const ICON_MAP = { ASTR:"icons/astr.svg", WBTC:"icons/bitcoin.svg", DOT:"icons/dot.svg", WETH:"icons/weth.svg", USDC:"icons/usdc.svg" };
    const tbody = getEl("marketsBody");
    tbody.innerHTML = "";
    
    const blocksPerYear = ACTIVE.blocksPerYear || 15768000;
    const master = new ethers.Contract(ACTIVE.master, window.MASTER_ABI, provider);
    
    let oracle = null;
    try {
        const oracleAddr = await master.oracle();
        oracle = new ethers.Contract(oracleAddr, window.ORACLE_ABI, provider);
    } catch(e) {}

    let globalSupplyUSD = 0;
    let globalBorrowUSD = 0;
    let globalReservesUSD = 0;

    for(const m of ACTIVE.cTokens) {
        try {
            const c = new ethers.Contract(m.address, window.C_TOKEN_ABI, provider);
            const underlyingDecimals = m.underlyingDecimals || 18;

            const [totalSupplyRaw, totalBorrowsRaw, totalReservesRaw, exchRateRaw, rates, priceRaw] = await Promise.all([
                c.totalSupply(), c.totalBorrows(), c.totalReserves(), c.exchangeRateStored(), c.peekRates(),
                oracle ? oracle.getUnderlyingPrice(m.address) : 0n
            ]);

            const priceUSD = oracle && priceRaw > 0n ? parseFloat(ethers.formatUnits(priceRaw, 18)) : 0;
            const totalSupplyUnderlying = (Number(totalSupplyRaw) * Number(exchRateRaw)) / 1e36;
            const totalSupplyUSD = totalSupplyUnderlying * priceUSD;
            const totalBorrowsUnderlying = Number(totalBorrowsRaw) / Math.pow(10, underlyingDecimals);
            const totalBorrowsUSD = totalBorrowsUnderlying * priceUSD;
            const totalReservesUSD = (Number(totalReservesRaw) / Math.pow(10, underlyingDecimals)) * priceUSD;

            const supplyAPY = rates && rates[1] ? ratePerBlockToAPY(rates[1], blocksPerYear) : 0;
            const borrowAPY = rates && rates[0] ? ratePerBlockToAPY(rates[0], blocksPerYear) : 0;
            const utilRate = totalSupplyUnderlying > 0 ? (totalBorrowsUnderlying / totalSupplyUnderlying) * 100 : 0;

            globalSupplyUSD += totalSupplyUSD;
            globalBorrowUSD += totalBorrowsUSD;
            globalReservesUSD += totalReservesUSD;

            const uSym = m.underlyingSymbol || m.symbol.replace(/^c/,"");
            const icon = m.icon || ICON_MAP[uSym] || "icons/unknown.svg";
            const displayDec = (uSym === 'WBTC' || uSym === 'BTC') ? 6 : 2;

            const tr = document.createElement("tr");
            tr.innerHTML = `
                <td>
                    <div class="asset-flex"><img src="${icon}" class="asset-icon"><div><div>${uSym}</div><div style="font-size:0.7em; color:var(--text-muted);">${m.symbol}</div></div></div>
                </td>
                <td><div>$${formatCompact(totalSupplyUSD)}</div><div style="font-size:0.75em; color:var(--text-muted);">${formatNumber(totalSupplyUnderlying, displayDec)} ${uSym}</div></td>
                <td><div>$${formatCompact(totalBorrowsUSD)}</div><div style="font-size:0.75em; color:var(--text-muted);">${formatNumber(totalBorrowsUnderlying, displayDec)} ${uSym}</div></td>
                <td><div style="color:var(--warning)">$${formatCompact(totalReservesUSD)}</div></td>
                <td><span class="text-green">${supplyAPY.toFixed(2)}%</span></td>
                <td><span class="text-yellow">${borrowAPY.toFixed(2)}%</span></td>
                <td style="min-width:120px;"><div style="display:flex; justify-content:space-between; font-size:0.75rem;"><span>${utilRate.toFixed(1)}%</span></div><div class="util-bar-bg"><div class="util-bar-fill" style="width:${Math.min(100, utilRate)}%"></div></div></td>
            `;
            tbody.appendChild(tr);
        } catch(e) { console.error("Row Error", e); }
    }

    animateValue("totalMarketSize", globalSupplyUSD);
    animateValue("totalBorrows", globalBorrowUSD);
    animateValue("totalTVL", globalSupplyUSD - globalBorrowUSD);
    animateValue("totalReserves", globalReservesUSD);
}

function formatNumber(n, dp=2) { return Number(n).toLocaleString('en-US', {minimumFractionDigits:dp, maximumFractionDigits:dp}); }
function formatCompact(n) { return Intl.NumberFormat('en-US', { notation: "compact", maximumFractionDigits: 2 }).format(n); }
function ratePerBlockToAPY(rate, blocks) { const r = Number(rate)/1e18; return r <= 0 ? 0 : ((Math.pow(1+r, blocks)-1)*100); }
function animateValue(id, endValue) {
    const el = getEl(id);
    if(!el) return;
    const current = parseFloat(el.innerText.replace('$','').replace(/,/g,'')) || 0;
    el.textContent = "$" + endValue.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2});
}