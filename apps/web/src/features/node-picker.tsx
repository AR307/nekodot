import { useRef } from 'react';
import { useAppStore } from '../store';
import { Icon } from '../ui';
import type { Texts } from '../shared';

export function NodePicker({ t }: { t: Texts }) {
  const nodes = useAppStore((state) => state.me?.nodes ?? []);
  const selectedId = useAppStore((state) => state.selectedNodeId);
  const menu = useRef<HTMLDetailsElement>(null);
  const selected = nodes.find((node) => node.nodeId === selectedId);
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
        <span className={`node-icon${selected?.online ? ' online' : ''}`}>
          <Icon name="laptop" />
        </span>
        <span className="node-picker-copy">
          <strong>{selected?.name ?? t.chooseComputer}</strong>
          <small className={selected?.online ? 'is-online' : 'is-offline'}>
            <i />
            {selected?.online ? t.connected : t.offline}
          </small>
        </span>
        <Icon name="chevron" />
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
            <span className="node-picker-copy">
              <strong>{node.name}</strong>
              <small>{node.online ? t.connected : t.offline}</small>
            </span>
            {selectedId === node.nodeId && <span className="node-selected">✓</span>}
          </button>
        ))}
        <button
          role="menuitem"
          className="node-menu-add"
          onClick={() => useAppStore.getState().setScreen('pair')}
        >
          <Icon name="plus" />
          {t.addComputer}
        </button>
      </div>
    </details>
  );
}
