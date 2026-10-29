import { useRef } from 'react';
import { useAppStore } from '../store';
import { Icon, StatusDot } from '../ui';
import type { Texts } from '../shared';

export function NodePicker({ t, state }: { t: Texts; state: 'ok' | 'connecting' | 'offline' }) {
  const nodes = useAppStore((store) => store.me?.nodes ?? []);
  const selectedId = useAppStore((store) => store.selectedNodeId);
  const menu = useRef<HTMLDetailsElement>(null);
  const selected = nodes.find((node) => node.nodeId === selectedId);
  const label = state === 'ok' ? t.synced : state === 'connecting' ? t.reconnecting : t.offline;
  return (
    <details
      className="node-picker"
      ref={menu}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) event.currentTarget.open = false;
      }}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          event.currentTarget.open = false;
          event.currentTarget.querySelector('summary')?.focus();
        }
      }}
    >
      <summary aria-label={t.chooseNode}>
        <StatusDot state={state} />
        <span className="node-picker-copy">
          <strong>{selected?.name ?? t.chooseComputer}</strong>
          <small>· {label}</small>
        </span>
        <Icon name="chevronDown" />
      </summary>
      <div className="node-menu" role="menu" aria-label={t.chooseComputer}>
        {nodes.map((node) => (
          <button
            role="menuitemradio"
            aria-checked={selectedId === node.nodeId}
            key={node.nodeId}
            onClick={() => {
              useAppStore.getState().setSelectedNode(node.nodeId);
              if (menu.current) menu.current.open = false;
            }}
          >
            <span className={`node-icon${node.online ? ' online' : ''}`}>
              <Icon name="laptop" />
            </span>
            <span className="node-menu-copy">
              <strong>{node.name}</strong>
              <small>{node.online ? t.connected : t.offline}</small>
            </span>
            {selectedId === node.nodeId && (
              <span className="node-selected">
                <Icon name="check" />
              </span>
            )}
          </button>
        ))}
        <button
          role="menuitem"
          className="node-menu-add"
          onClick={() => useAppStore.getState().setScreen('pair')}
        >
          <span className="node-icon">
            <Icon name="plus" />
          </span>
          {t.addComputer}
        </button>
      </div>
    </details>
  );
}
