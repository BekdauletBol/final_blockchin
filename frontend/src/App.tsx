import { WalletButton } from "./components/WalletButton";
import { PortfolioPanel } from "./components/PortfolioPanel";
import { MarketPanel } from "./components/MarketPanel";
import { AnalyticsPanel } from "./components/AnalyticsPanel";
import { GovernancePanel } from "./components/GovernancePanel";

function App() {
  return (
    <div className="container">
      <header>
        <div className="brand">
          <h1>Prediction Market</h1>
          <span className="network-badge">Arbitrum Sepolia</span>
        </div>
        <WalletButton />
      </header>

      <main className="grid">
        <section className="col-main">
          <MarketPanel />
          <GovernancePanel />
        </section>
        
        <section className="col-sidebar">
          <PortfolioPanel />
          <AnalyticsPanel />
        </section>
      </main>

      <footer>
        <p>Built for Bekdaulet — 2026</p>
      </footer>
    </div>
  );
}

export default App;
