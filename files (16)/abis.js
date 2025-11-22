// ABIs global para cToken, Master, ERC20

window.C_TOKEN_ABI = [
  // Constructor (no lo necesita el frontend, pero no afecta)
  { "inputs":[
      {"internalType":"string","name":"_n","type":"string"},
      {"internalType":"string","name":"_s","type":"string"},
      {"internalType":"address","name":"_underlying","type":"address"},
      {"internalType":"address","name":"_comptroller","type":"address"},
      {"internalType":"address","name":"_guardian","type":"address"},
      {"internalType":"address","name":"_irm","type":"address"},
      {"internalType":"uint256","name":"_reserveFactorMantissa","type":"uint256"}
    ],"stateMutability":"nonpayable","type":"constructor"},
  // cToken methods
  { "inputs": [], "name": "name", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "symbol", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "decimals", "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "totalSupply", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "totalBorrows", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
  { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "balanceOf", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
  { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "borrowBalance", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "peekRates", "outputs": [
      { "internalType": "uint256", "name": "borrowRatePerBlock", "type": "uint256" },
      { "internalType": "uint256", "name": "supplyRatePerBlock", "type": "uint256" },
      { "internalType": "uint256", "name": "utilization", "type": "uint256" }
    ], "stateMutability": "view", "type": "function" },
  { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "mint", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
  { "inputs": [{ "internalType": "uint256", "name": "cTokenAmount", "type": "uint256" }], "name": "redeem", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
  { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "borrow", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
  { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "repay", "outputs": [], "stateMutability": "nonpayable", "type": "function" },
  { "inputs": [], "name": "underlying", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" },
  // exchange rate functions (¡necesarias para frontend!)
  { "inputs": [], "name": "exchangeRateStored", "outputs": [{"internalType": "uint256","name":"","type":"uint256"}], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "exchangeRateInitialMantissa", "outputs": [{"internalType": "uint256","name":"","type":"uint256"}], "stateMutability": "view", "type": "function" },
  { "inputs": [], "name": "accrualBlockNumber", "outputs": [{"internalType": "uint256","name":"","type":"uint256"}], "stateMutability": "view", "type": "function" }
];

window.MASTER_ABI = [
  { "inputs":[{"internalType":"address[]","name":"cTokens","type":"address[]"}],"name":"enterMarkets","outputs":[],"stateMutability":"nonpayable","type":"function"},
  { "inputs":[{"internalType":"address","name":"account","type":"address"}],"name":"getAccountLiquidity","outputs":[
      {"components":[
        {"internalType":"uint256","name":"collateralUSD","type":"uint256"},
        {"internalType":"uint256","name":"liquidationUSD","type":"uint256"},
        {"internalType":"uint256","name":"borrowUSD","type":"uint256"}
      ],"internalType":"struct LiquidityData","name":"ld","type":"tuple"}
    ],"stateMutability":"view","type":"function"}
];

window.MIN_ERC20_ABI = [
  { name:"allowance", type:"function", stateMutability:"view",
    inputs:[{name:"owner",type:"address"},{name:"spender",type:"address"}],
    outputs:[{name:"",type:"uint256"}] },
  { name:"approve", type:"function", stateMutability:"nonpayable",
    inputs:[{name:"spender",type:"address"},{name:"amount",type:"uint256"}],
    outputs:[{name:"",type:"bool"}] },
  { name:"balanceOf", type:"function", stateMutability:"view",
    inputs:[{name:"owner",type:"address"}],
    outputs:[{name:"",type:"uint256"}] },
  { name:"decimals", type:"function", stateMutability:"view",
    inputs:[], outputs:[{name:"",type:"uint8"}] }
];
