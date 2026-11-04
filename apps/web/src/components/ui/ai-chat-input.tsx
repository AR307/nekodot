import { useState, type FormEventHandler, type ReactNode } from 'react';

/** Drafts and actions belong to the caller; this component owns only the capsule layout. */
export function PromptInput({
  children,
  tools,
  action,
  attachments,
  hasContent,
  running,
  onSubmit,
}: {
  children: ReactNode;
  tools: ReactNode;
  action: ReactNode;
  attachments?: ReactNode;
  hasContent: boolean;
  running: boolean;
  onSubmit: FormEventHandler<HTMLFormElement>;
}) {
  const [focused, setFocused] = useState(false);
  const expanded = focused || hasContent || running;
  return (
    <form
      className={`composer prompt-input${expanded ? ' is-expanded' : ''}${running ? ' is-running' : ''}`}
      onSubmit={onSubmit}
      onFocus={() => setFocused(true)}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setFocused(false);
      }}
    >
      {attachments}
      <div className="prompt-field">{children}</div>
      <div className="prompt-toolbar">
        <div className="prompt-tools" inert={!expanded}>
          {tools}
        </div>
        {action}
      </div>
    </form>
  );
}
