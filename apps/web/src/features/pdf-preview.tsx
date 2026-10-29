import { useEffect, useRef, useState } from 'react';
import { getDocument, GlobalWorkerOptions } from 'pdfjs-dist';
import worker from 'pdfjs-dist/build/pdf.worker.min.mjs?url';

GlobalWorkerOptions.workerSrc = worker;

export function PdfPreview({ url, title }: { url: string; title: string }) {
  const container = useRef<HTMLDivElement>(null);
  const [error, setError] = useState('');
  useEffect(() => {
    const task = getDocument({ url });
    let disposed = false;
    void task.promise
      .then(async (pdf) => {
        for (let number = 1; number <= pdf.numPages && !disposed; number++) {
          const page = await pdf.getPage(number);
          if (disposed) return;
          const canvas = document.createElement('canvas');
          const width = Math.min(container.current!.clientWidth || 760, 1200);
          const viewport = page.getViewport({
            scale: width / page.getViewport({ scale: 1 }).width,
          });
          canvas.width = viewport.width;
          canvas.height = viewport.height;
          canvas.setAttribute('aria-label', `${title} · ${number}/${pdf.numPages}`);
          container.current!.append(canvas);
          await page.render({ canvas, viewport }).promise;
        }
      })
      .catch((reason: Error) => {
        if (!disposed) setError(reason.message);
      });
    const element = container.current;
    return () => {
      disposed = true;
      void task.destroy();
      element?.replaceChildren();
    };
  }, [url, title]);
  return (
    <div className="pdf-pages" ref={container}>
      {error && <p role="alert">{error}</p>}
    </div>
  );
}
