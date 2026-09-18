import { Controller } from "@hotwired/stimulus"

// Selection mode and the fixed image sit in their own form, so the pool can save
// them without leaving the wizard, and that form cannot nest inside the event
// form. The wizard saves the event from whichever step is open, which would
// otherwise drop edits made here and report success anyway. This copies them
// into every other form that saves the event.
export default class extends Controller {
  static values = { formIds: Array }

  connect() {
    this.carry = this.carry.bind(this)
    this.carried = new Map()

    this.forms = this.formIdsValue
      .map((formId) => document.getElementById(formId))
      .filter((form) => form && form !== this.element)

    this.forms.forEach((form) => form.addEventListener("submit", this.carry))
  }

  disconnect() {
    this.forms.forEach((form) => form.removeEventListener("submit", this.carry))
    this.forms.forEach((form) => this.discard(form))
  }

  carry(event) {
    const form = event.currentTarget
    this.discard(form)

    this.carried.set(
      form,
      this.settings().map(([name, value]) => {
        const input = document.createElement("input")
        input.type = "hidden"
        input.name = name
        input.value = value
        form.appendChild(input)

        return input
      })
    )
  }

  // Only this form's own event attributes: the CSRF token and _method belong to
  // the form they came from, and a file cannot ride along in a hidden field.
  settings() {
    return Array.from(this.element.elements)
      .filter((field) => field.name.startsWith("event[") && field.type !== "file")
      .filter((field) => !["radio", "checkbox"].includes(field.type) || field.checked)
      .map((field) => [field.name, field.value])
  }

  discard(form) {
    const inputs = this.carried.get(form)
    if (!inputs) return

    inputs.forEach((input) => input.remove())
    this.carried.delete(form)
  }
}
