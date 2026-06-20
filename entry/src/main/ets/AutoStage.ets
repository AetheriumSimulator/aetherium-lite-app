let autoStageRuntime: boolean = false

export function setAutoStageRuntime(value: boolean): void {
  autoStageRuntime = value
}

export function consumeAutoStageRuntime(): boolean {
  const value = autoStageRuntime
  autoStageRuntime = false
  return value
}
