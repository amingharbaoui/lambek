// Icons drawn on the same 24 × 24 grid and stroke as lucide

// A ghost whose eyes are two linked nodes: incognito, the Lambek way
export function GhostNodes({ size = 24, strokeWidth = 2, className }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M5 21V11a7 7 0 0 1 14 0v10l-2.33-1.75L14.33 21 12 19.25 9.67 21l-2.34-1.75z" />
      <circle cx="9.5" cy="11" r="1" fill="currentColor" />
      <circle cx="14.5" cy="11" r="1" fill="currentColor" />
      <path d="M10.5 11h3" strokeWidth="1.25" />
    </svg>
  );
}

function Frame({ size, strokeWidth, className, children }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

// A sheet and its dashed slot, like the empty slot of a proof line: copy
export function CopySlot({ size = 24, strokeWidth = 2, className }) {
  return (
    <Frame size={size} strokeWidth={strokeWidth} className={className}>
      <rect width="14" height="14" x="8" y="8" rx="2" ry="2" />
      <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" strokeDasharray="3 3.2" />
    </Frame>
  );
}

// A check that draws itself like a proof arc: copied
export function CheckArc({ size = 24, strokeWidth = 2, className }) {
  return (
    <Frame size={size} strokeWidth={strokeWidth} className={`check-arc ${className ?? ""}`}>
      <path pathLength="1" d="M20 6 9 17l-5-5" />
    </Frame>
  );
}
