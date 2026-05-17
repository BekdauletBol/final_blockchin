import { createConfig, http } from "wagmi";
import { arbitrumSepolia }    from "wagmi/chains";
import { metaMask, walletConnect } from "@wagmi/connectors";

// WalletConnect project ID — replace with your own from https://cloud.walletconnect.com
const WC_PROJECT_ID = import.meta.env.VITE_WC_PROJECT_ID ?? "YOUR_PROJECT_ID";

export const wagmiConfig = createConfig({
  chains:      [arbitrumSepolia],
  connectors:  [
    metaMask(),
    walletConnect({ projectId: WC_PROJECT_ID }),
  ],
  transports: {
    [arbitrumSepolia.id]: http(import.meta.env.VITE_RPC_URL ?? undefined),
  },
});
