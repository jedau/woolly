export function moneyForecast(input: {
  payCents: number;
  totalEffort: number;
  acceptedEffort: number;
  lockedAt: Date | null;
  deadline: string | null;
}) {
  const acceptedCents =
    input.totalEffort === 0 ? 0 : Math.round((input.payCents * input.acceptedEffort) / input.totalEffort);

  if (!input.deadline || !input.lockedAt) {
    return { acceptedCents, projectedCents: acceptedCents };
  }

  const day = 86_400_000;
  const locked = Date.parse(input.lockedAt.toISOString().slice(0, 10));
  const deadline = Date.parse(input.deadline);
  const today = Date.parse(new Date().toISOString().slice(0, 10));
  const totalDays = Math.max(1, Math.round((deadline - locked) / day));
  const elapsed = Math.max(0, Math.round((today - locked) / day));
  const daysLeft = Math.max(0, totalDays - elapsed);
  const pace = input.acceptedEffort / Math.max(elapsed, 1);
  const projectedEffort = Math.min(input.totalEffort, input.acceptedEffort + pace * daysLeft);
  const projectedCents =
    input.totalEffort === 0 ? 0 : Math.round((input.payCents * projectedEffort) / input.totalEffort);
  return { acceptedCents, projectedCents };
}
