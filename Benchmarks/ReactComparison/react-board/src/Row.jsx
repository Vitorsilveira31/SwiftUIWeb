import { memo } from "react";

// A row of the list. memo keeps a row that did not change out of the render, the way a React developer writes a long list.
export const Row = memo(function Row({ work, isFavorite, isSelected, onToggleFavorite, onSelect }) {
  return (
    <div data-testid="row" data-id={work.id} className={isSelected ? "row selected" : "row"}>
      <span className="title" data-testid={`title-${work.id}`} onClick={() => onSelect(work.id)}>{work.title}</span>
      <span className="status">{work.status}</span>
      <button
        type="button"
        data-testid={`fav-${work.id}`}
        aria-pressed={isFavorite}
        aria-label="Favorite"
        onClick={() => onToggleFavorite(work.id)}
      >
        {isFavorite ? "★" : "☆"}
      </button>
    </div>
  );
});
