import { useAccount, useConnect, useDisconnect } from "wagmi";

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connectors, connect } = useConnect();
  const { disconnect } = useDisconnect();

  if (isConnected) {
    return (
      <div className="wallet-info">
        <span>{address?.slice(0, 6)}...{address?.slice(-4)}</span>
        <button onClick={() => disconnect()} className="btn-secondary">Disconnect</button>
      </div>
    );
  }

  return (
    <div className="wallet-connect">
      {connectors.map((connector) => (
        <button
          key={connector.uid}
          onClick={() => connect({ connector })}
          className="btn-primary"
        >
          Connect {connector.name}
        </button>
      ))}
    </div>
  );
}
