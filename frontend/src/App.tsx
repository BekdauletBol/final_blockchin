import { WalletButton } from "./components/WalletButton";
import { PortfolioPanel } from "./components/PortfolioPanel";
import { MarketPanel } from "./components/MarketPanel";
import { AnalyticsPanel } from "./components/AnalyticsPanel";

function App() {
  return (
    <div className="container">
      <header>
        <h1>Prediction Market dApp</h1>
        <WalletButton />
      </header>

      <main className="grid">
        <section className="col-left">
          <MarketPanel />
          <PortfolioPanel />
        </section>
        
        <section className="col-right">
          <AnalyticsPanel />
        </section>
      </main>

      <footer>
        <p>Built for Arbitrum Sepolia</p>
      </footer>
    </div>
  );
}

export default App;
