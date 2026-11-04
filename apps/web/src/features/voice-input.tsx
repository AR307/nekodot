import { useEffect, useRef, useState } from 'react';
import { callNode } from '../relay-connection';
import { useAppStore } from '../store';
import { pcmWave } from '../audio';
import { LoadingText } from '../ui';

export function VoiceInput({
  botId,
  disabled,
  onTranscript,
  onError,
  onBusy,
}: {
  botId: string;
  disabled: boolean;
  onTranscript(text: string): void;
  onError(message: string): void;
  onBusy(value: boolean): void;
}) {
  const zh = useAppStore((state) => state.language === 'zh');
  const [phase, setPhase] = useState<'idle' | 'starting' | 'recording' | 'transcribing'>('idle');
  const recorder = useRef<MediaRecorder | null>(null);
  const alive = useRef(true);
  const generation = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => {
    alive.current = true;
    const cancel = () => {
      generation.current++;
      const current = recorder.current;
      if (current) {
        current.onstop = null;
        if (current.state !== 'inactive') current.stop();
        current.stream.getTracks().forEach((track) => track.stop());
        recorder.current = null;
      }
      clearTimeout(timer.current);
    };
    const hide = () => {
      if (document.hidden) {
        cancel();
        setPhase('idle');
        onBusy(false);
      }
    };
    document.addEventListener('visibilitychange', hide);
    return () => {
      alive.current = false;
      cancel();
      onBusy(false);
      document.removeEventListener('visibilitychange', hide);
    };
  }, [onBusy]);

  async function start() {
    if (phase !== 'idle') return;
    const ticket = ++generation.current;
    const nodeId = useAppStore.getState().selectedNodeId;
    setPhase('starting');
    onBusy(true);
    try {
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder)
        throw new Error(
          zh
            ? '此浏览器不支持录音，请使用 Windows 客户端。'
            : 'Recording is unavailable. Use the Windows client.',
        );
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!alive.current || document.hidden || ticket !== generation.current) {
        stream.getTracks().forEach((track) => track.stop());
        return;
      }
      const chunks: Blob[] = [];
      let current: MediaRecorder;
      try {
        current = new MediaRecorder(stream);
      } catch (error) {
        stream.getTracks().forEach((track) => track.stop());
        throw error;
      }
      recorder.current = current;
      current.ondataavailable = (event) => {
        if (event.data.size) chunks.push(event.data);
      };
      current.onstop = () => {
        stream.getTracks().forEach((track) => track.stop());
        clearTimeout(timer.current);
        recorder.current = null;
        void transcribe(new Blob(chunks, { type: current.mimeType }), nodeId, ticket);
      };
      current.onerror = () => {
        current.onstop = null;
        stream.getTracks().forEach((track) => track.stop());
        clearTimeout(timer.current);
        recorder.current = null;
        if (alive.current && ticket === generation.current) {
          setPhase('idle');
          onBusy(false);
          onError(zh ? '录音失败，请重试。' : 'Recording failed. Try again.');
        }
      };
      current.start();
      setPhase('recording');
      timer.current = setTimeout(() => {
        if (current.state === 'recording') current.stop();
      }, 60_000);
    } catch (error) {
      const current = recorder.current;
      if (current) {
        current.onstop = null;
        current.stream.getTracks().forEach((track) => track.stop());
        recorder.current = null;
      }
      clearTimeout(timer.current);
      if (alive.current && ticket === generation.current) {
        setPhase('idle');
        onBusy(false);
        onError(error instanceof Error ? error.message : String(error));
      }
    }
  }

  async function transcribe(blob: Blob, nodeId: string | null, ticket: number) {
    if (!alive.current) return;
    setPhase('transcribing');
    try {
      const context = new AudioContext();
      let decoded: AudioBuffer;
      try {
        decoded = await context.decodeAudioData(await blob.arrayBuffer());
      } finally {
        await context.close();
      }
      const offline = new OfflineAudioContext(1, Math.ceil(decoded.duration * 16000), 16000);
      const source = offline.createBufferSource();
      source.buffer = decoded;
      source.connect(offline.destination);
      source.start();
      const pcm = (await offline.startRendering()).getChannelData(0);
      const bytes = new Uint8Array(pcmWave(pcm));
      let binary = '';
      for (let start = 0; start < bytes.length; start += 8192)
        binary += String.fromCharCode(...bytes.subarray(start, start + 8192));
      const checkTarget = () => {
        if (
          !alive.current ||
          ticket !== generation.current ||
          useAppStore.getState().selectedNodeId !== nodeId
        )
          throw new Error(zh ? '电脑已切换，请重新录音。' : 'Computer changed. Record again.');
      };
      checkTarget();
      let operation = await callNode('voice.transcribe', {
        botId,
        audio: 'data:audio/wav;base64,' + btoa(binary),
      });
      const deadline = Date.now() + 120_000;
      while (operation.status === 'running') {
        if (Date.now() > deadline)
          throw new Error(zh ? '语音识别超时，请重试。' : 'Transcription timed out. Try again.');
        await new Promise((resolve) => setTimeout(resolve, 1000));
        checkTarget();
        operation = await callNode('operations.get', { operationId: operation.operationId });
      }
      checkTarget();
      if (operation.status !== 'done') throw new Error(operation.detail);
      const native = operation.results[0]?.native as { transcript?: string } | undefined;
      if (typeof native?.transcript !== 'string' || !native.transcript.trim())
        throw new Error(zh ? '没有识别到文字，请重试。' : 'No transcript. Try again.');
      onTranscript(native.transcript);
    } catch (error) {
      if (alive.current && ticket === generation.current)
        onError(error instanceof Error ? error.message : String(error));
    } finally {
      if (alive.current && ticket === generation.current) {
        setPhase('idle');
        onBusy(false);
      }
    }
  }

  const label =
    phase === 'recording'
      ? zh
        ? '停止并识别'
        : 'Stop and transcribe'
      : phase === 'transcribing'
        ? zh
          ? '正在识别'
          : 'Transcribing'
        : zh
          ? '语音输入'
          : 'Voice input';
  return (
    <button
      className={`send-button voice-input ${phase}`}
      type="button"
      aria-label={label}
      title={label}
      disabled={
        phase === 'starting' || phase === 'transcribing' || (disabled && phase !== 'recording')
      }
      onClick={() => (phase === 'recording' ? recorder.current?.stop() : void start())}
    >
      {phase === 'transcribing' || phase === 'starting' ? (
        <LoadingText text={zh ? '识别中' : 'STT'} />
      ) : phase === 'recording' ? (
        <span className="prompt-stop" />
      ) : (
        <svg
          viewBox="0 0 24 24"
          width="17"
          height="17"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.7"
          aria-hidden="true"
        >
          <rect x="9" y="3" width="6" height="12" rx="3" />
          <path d="M6 11v1a6 6 0 0 0 12 0v-1M12 18v3" />
        </svg>
      )}
    </button>
  );
}
