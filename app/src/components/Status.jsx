// The working mark: a type, then a pair x^l x that cancels under its arc, leaving s
export function ReductionMark() {
  return (
    <svg className="reduction-mark" width="30" height="20" viewBox="0 0 30 20" aria-hidden="true">
      <circle className="kept" cx="5" cy="6" r="2.4" />
      <circle className="pair left" cx="15" cy="6" r="2.4" />
      <circle className="pair right" cx="25" cy="6" r="2.4" />
      <path className="cup" pathLength="1" d="M15 9 C15 17, 25 17, 25 9" />
    </svg>
  );
}

// Compacting a long chat: the mark, what happens, and the only progress bar of the app
export function Working({ word, percent, progress }) {
  const value = Math.max(0, Math.min(100, Math.round(percent ?? 0)));

  return (
    <div className="status" role="status" aria-live="polite">
      <ReductionMark />
      <div className="status-body">
        <span className="status-word">{word}…</span>
        {progress && (
          <span className="progress">
            <span className="progress-track">
              <span className="progress-fill" style={{ width: `${value}%` }} />
            </span>
            <span className="progress-value">{value}%</span>
          </span>
        )}
      </div>
    </div>
  );
}
