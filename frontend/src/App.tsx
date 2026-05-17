import React, { useState }              from "react";
import { WagmiProvider, useAccount, useSwitchChain, useChainId } from "wagmi";
import { QueryClient, QueryClientProvider }                       from "@tanstack/react-query";
import { arbitrumSepolia }                                        from "wagmi/chains";
import { wagmiConfig }                                            from "./wagmi";
import { WalletButton }     from "./components/WalletButton";
import { MarketPanel }      from "./components/MarketPanel";
import { GovernancePanel }  from "./components/GovernancePanel";
import { PortfolioPanel }   from "./components/PortfolioPanel";
import { AnalyticsPanel }   from "./components/AnalyticsPanel";

const queryClient = new QueryClient();

type Tab = "market" | "governance" | "portfolio" | "analytics";

function Inner() {
  const { isConnected } = useAccount();
  const chainId         = useChainId();
  const { switchChain } = useSwitchChain();
  const [tab, setTab]   = useState<Tab>("market");

  const wrongNetwork = isConnected && chainId !== arbitrumSepolia.id;

  return (
    <div style={styles.root}>
      {/* ── Header ── */}
      <header style={styles.header}>
        <span style={styles.logo}>🔮 PredMarket</span>
        <nav style={styles.nav}>
          {(["market","governance","portfolio","analytics"] as Tab[]).map(t => (
            <button key={t} onClick={() => setTab(t)}
              style={{ ...styles.navBtn, ...(tab === t ? styles.navActive : {}) }}>
              {t.charAt(0).toUpperCase() + t.slice(1)}
            </button>
          ))}
        </nav>
        <WalletButton />
      </header>

      {/* ── Wrong network banner ── */}
      {wrongNetwork && (
        <div style={styles.banner}>
          ⚠️ Wrong network — please switch to Arbitrum Sepolia.&nbsp;
          <button onClick={() => switchChain({ chainId: arbitrumSepolia.id })}
            style={styles.switchBtn}>
            Switch
          </button>
        </div>
      )}

      {/* ── Main content ── */}
      <main style={styles.main}>
        {tab === "market"      && <MarketPanel />}
        {tab === "governance"  && <GovernancePanel />}
        {tab === "portfolio"   && <PortfolioPanel />}
        {tab === "analytics"   && <AnalyticsPanel />}
      </main>
    </div>
  );
}

export default function App() {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <Inner />
      </QueryClientProvider>
    </WagmiProvider>
  );
}

const styles: Record<string, React.CSSProperties> = {
  root:      { fontFamily: "system-ui, sans-serif", minHeight: "100vh", background: "#0f0f13", color: "#e8e8f0" },
  header:    { display: "flex", alignItems: "center", justifyContent: "space-between", padding: "16px 32px",
               borderBottom: "1px solid #2a2a3a", background: "#16161f" },
  logo:      { fontSize: 22, fontWeight: 700, letterSpacing: -0.5 },
  nav:       { display: "flex", gap: 8 },
  navBtn:    { background: "none", border: "none", color: "#9898b0", cursor: "pointer",
               padding: "6px 14px", borderRadius: 8, fontSize: 15, transition: "all .15s" },
  navActive: { background: "#252535", color: "#e8e8f0" },
  banner:    { background: "#3a1a00", color: "#ffb347", padding: "10px 32px",
               display: "flex", alignItems: "center", gap: 8 },
  switchBtn: { background: "#ff7b00", border: "none", borderRadius: 6, color: "#fff",
               cursor: "pointer", padding: "4px 14px", fontWeight: 600 },
  main:      { maxWidth: 960, margin: "32px auto", padding: "0 24px" },
};
