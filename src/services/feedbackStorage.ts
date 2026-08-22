import type { Feedback } from "../types/Feedback";

const STORAGE_KEY = "feedback-control-feedbacks";

export function getFeedbacks(): Feedback[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) {
    return [];
  }

  return JSON.parse(data) as Feedback[];
}

export function getFeedbacksByColaborador(colaboradorId: number): Feedback[] {
  const feedbacks = getFeedbacks();

  return feedbacks.filter(
    (feedback) => feedback.colaboradorId === colaboradorId
  );
}

export function saveFeedback(feedback: Feedback): void {
  const feedbacks = getFeedbacks();

  const updatedFeedbacks = [...feedbacks, feedback];

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(updatedFeedbacks)
  );
}

export function deleteFeedback(
  feedbackId: string
): void {
  const feedbacks = getFeedbacks();

  const updatedFeedbacks = feedbacks.filter(
    (feedback) => feedback.id !== feedbackId
  );

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(updatedFeedbacks)
  );
}

export function updateFeedback(
  updatedFeedback: Feedback
): void {
  const feedbacks = getFeedbacks();

  const updatedFeedbacks = feedbacks.map(
    (feedback) =>
      feedback.id === updatedFeedback.id
        ? updatedFeedback
        : feedback
  );

  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify(updatedFeedbacks)
  );
}
