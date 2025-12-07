// wallet-config.js – VERSIÓN DEFINITIVA FIXED 2025 – BASADA EN DOCS OFICIAL TRUST WALLET
(function () {
  const WALLET_ICONS = {
    metamask: `<svg viewBox="0 0 32 32" width="32" height="32"><path fill="#E17726" d="M29.2 10.8l-2.4-5.6-5.8 2-3.8-2.6h-2.3l-3.8 2.6-5.8-2-2.4 5.6c-1.3 2.1-1.6 6.8 2.6 11.2 0 0 1.2 2.6 5.5 2.6l1.3-1.6 1.7 1.8h3.9l1.7-1.8 1.3 1.6c4.3 0 5.5-2.6 5.5-2.6 4.3-4.5 3.9-9.1 2.6-11.2z"/></svg>`,
    trust: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32"><rect width="32" height="32" rx="8" fill="#3375BB"/><path fill="#FFF" d="M16 6.5a7.5 7.5 0 0 1 7.5 7.5c0 5-7.5 12.5-7.5 12.5s-7.5-7.5-7.5-12.5A7.5 7.5 0 0 1 16 6.5m0 4a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z"/></svg>`,
    nova: `<svg viewBox="0 0 32 32" width="32" height="32"><circle cx="16" cy="16" r="16" fill="url(#nova-grad)"/><defs><linearGradient id="nova-grad" x1="0%" y1="0%" x2="100%" y2="100%"><stop offset="0%" stop-color="#3C95FF"/><stop offset="100%" stop-color="#2D6CDF"/></linearGradient></defs><path fill="#FFF" d="M16 6l-6 10h12L16 6zm-6 12l-4 7h20l-4-7H10z"/></svg>`,
    walletconnect: `<svg viewBox="0 0 32 32" width="32" height="32"><path fill="#3B99FC" d="M6.5 8.5a1.5 1.5 0 0 1 1.5-1.5h16a1.5 1.5 0 0 1 1.5 1.5v15a1.5 1.5 0 0 1-1.5 1.5h-16a1.5 1.5 0 0 1-1.5-1.5v-15z"/><path fill="#FFF" d="M10 16c0-3.3 2.7-6 6-6s6 2.7 6 6-2.7 6-6 6-6-2.7-6-6z"/></svg>`
  };

  const WALLETS = [
    {
      id: "metamask",
      name: "MetaMask",
      icon: WALLET_ICONS.metamask,
      check: () => window.ethereum?.isMetaMask && !window.ethereum?.isTrust,
      getProvider: () => window.ethereum,
      mobileDeepLink: () => `https://metamask.app.link/dapp/${window.location.host}${window.location.pathname}`
    },
    {
      id: "trust",
      name: "Trust Wallet",
      icon: WALLET_ICONS.trust,
      check: () => {
        if (window.trustwallet) return true;
        if (window.ethereum?.isTrust) return true;
        if (navigator.userAgent.toLowerCase().includes("trust")) return true;
        if (window.ethereum?.providers?.some(p => p.isTrust || p.isTrustWallet)) return true;
        return false;
      },
      getProvider: () => window.trustwallet || window.ethereum?.providers?.find(p => p.isTrust || p.isTrustWallet) || window.ethereum,
      mobileDeepLink: () => `https://link.trustwallet.com/open_url?coin_id=60&url=${encodeURIComponent(window.location.href)}`
    },
    {
      id: "nova",
      name: "Nova Wallet",
      icon: WALLET_ICONS.nova,
      description: "Polkadot · Ethereum",
      check: () => !!window.injectedWeb3?.["nova-wallet"] || (window.ethereum && !window.ethereum.isMetaMask && !window.ethereum.isTrust),
      getProvider: () => window.injectedWeb3?.["nova-wallet"] || window.ethereum,
      mobileDeepLink: () => `novawallet://dapp/${window.location.host}`
    },
    {
      id: "walletconnect",
      name: "WalletConnect",
      icon: WALLET_ICONS.walletconnect,
      check: () => true,
      connector: true,
      mobileDeepLink: () => `https://walletconnect.com/`
    }
  ];

  const isMobile = /Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ||
                   (navigator.userAgent.includes("Mac") && "ontouchend" in document); // Detecta iPadOS

  window.WALLET_CONFIG = {
    list: WALLETS,
    icons: WALLET_ICONS,
    getInjectedProvider: () => {
      for (const w of WALLETS) if (w.check() && !w.connector) return w.getProvider?.();
      return null;
    },
    openMobileLink: (walletId) => {
      const wallet = WALLETS.find(w => w.id === walletId);
      if (!wallet || !wallet.mobileDeepLink) return false;

      let url = wallet.mobileDeepLink();

      if (wallet.id === "trust" && !isMobile) {
        url = "https://trustwallet.com/browser-extension"; // Directo a extensión en PC
      } else if (wallet.id === "metamask" && !isMobile) {
        url = "https://metamask.io/download/";
      } else if (wallet.id === "nova" && !isMobile) {
        url = "https://novawallet.io/";
      }

      console.log(`%c[CONNECT DEBUG] Abriendo ${wallet.name} en ${isMobile ? 'móvil' : 'desktop'}: ${url}`, "color: #3375BB; font-weight: bold; font-size: 14px");

      if (isMobile) {
        window.location.href = url; // Reemplaza en móvil
      } else {
        window.open(url, "_blank"); // Nueva pestaña en PC
      }
      return true;
    }
  };

  console.log("%c[WALLET CONFIG] Versión DEFINITIVA FIXED 2025 – Basada en docs oficiales, sin errores de sintaxis 🔥", "color: #00aa00; font-weight: bold; font-size: 14px");
})();
