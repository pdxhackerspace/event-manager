import { Controller } from "@hotwired/stimulus"

// Reloads the scheduling conflict notice as the time, duration, or flags change.
export default class extends Controller {
  static targets = ["frame", "buffer", "override"]
  static values = { url: String, eventId: String, occurrenceId: String }

  connect() {
    this.onChange = () => this.schedule()
    this.element.addEventListener("change", this.onChange)
    this.element.addEventListener("input", this.onChange)
    this.toggleBuffer()
    this.schedule()
  }

  disconnect() {
    this.element.removeEventListener("change", this.onChange)
    this.element.removeEventListener("input", this.onChange)
    clearTimeout(this.timer)
  }

  frameLoaded() {
    if (!this.hasOverrideTarget) return

    this.overrideTarget.hidden = !this.frameTarget.querySelector("[data-exclusive-block]")
  }

  schedule() {
    this.toggleBuffer()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.load(), 400)
  }

  toggleBuffer() {
    if (!this.hasBufferTarget) return

    const form = this.element.closest("form") || this.element
    const busy = form.querySelector('[name="event[busy]"]')?.checked
    const exclusive = form.querySelector('[name="event[request_exclusive]"]')?.checked
    this.bufferTarget.hidden = !(busy || exclusive)
  }

  load() {
    if (!this.hasFrameTarget) return

    const params = this.params()
    if (this.hasEventIdValue && this.eventIdValue) params.set("event_id", this.eventIdValue)
    if (this.hasOccurrenceIdValue && this.occurrenceIdValue) params.set("occurrence_id", this.occurrenceIdValue)
    this.frameTarget.src = `${this.urlValue}?${params.toString()}`
  }

  params() {
    const form = this.element.closest("form") || this.element
    const params = new URLSearchParams()
    const names = [
      "event[start_time]", "event[duration]", "event[recurrence_type]",
      "event[busy]", "event[request_exclusive]", "event[conflict_buffer_minutes]",
      "event_occurrence[occurs_at]", "event_occurrence[duration_override]",
      "recurrence_interval", "recurrence_day"
    ]

    names.forEach((name) => this.appendFields(params, form, name))
    form.querySelectorAll(
      '[name="recurrence_days[]"]:checked, [name="recurrence_occurrences[]"]:checked, ' +
      '[name="recurrence_except_occurrences[]"]:checked, [name^="custom_rules"]'
    ).forEach((field) => {
      if (field.type === "checkbox" && !field.checked) return
      params.append(field.name, field.value)
    })

    return params
  }

  appendFields(params, form, name) {
    form.querySelectorAll(`[name="${name}"]`).forEach((field) => {
      if ((field.type === "checkbox" || field.type === "radio") && !field.checked) return
      params.append(field.name, field.value)
    })
  }
}
