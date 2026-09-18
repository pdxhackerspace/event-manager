import { Controller } from "@hotwired/stimulus"

// The image pool upload sits in its own form so "Add to Pool" can upload right
// away, which makes it easy to pick files and then save the event without ever
// clicking Add. This copies any still-unsent selection into every form that
// saves the event, so those uploads ride along instead of being discarded.
export default class extends Controller {
  static targets = ["input", "notice"]
  static values = { formIds: Array, fieldName: String }

  connect() {
    this.transfer = this.transfer.bind(this)
    this.carriers = new Map()

    this.forms = this.formIdsValue
      .map((formId) => document.getElementById(formId))
      .filter((form) => form)

    this.forms.forEach((form) => form.addEventListener("submit", this.transfer))
  }

  disconnect() {
    this.forms.forEach((form) => form.removeEventListener("submit", this.transfer))
    this.carriers.forEach((carrier) => carrier.remove())
    this.carriers.clear()
  }

  inputChanged() {
    if (!this.hasNoticeTarget) return

    const count = this.selectedFiles().length
    this.noticeTarget.classList.toggle("d-none", count === 0)
    if (count === 0) return

    const noun = count === 1 ? "image" : "images"
    this.noticeTarget.textContent =
      `${count} ${noun} selected. Click "Add to Pool" to upload now, or they will be uploaded when you save the event.`
  }

  transfer(event) {
    const files = this.selectedFiles()
    if (files.length === 0) return

    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    this.carrierInput(event.currentTarget).files = transfer.files
  }

  selectedFiles() {
    if (!this.hasInputTarget || !this.inputTarget.files) return []

    return Array.from(this.inputTarget.files)
  }

  carrierInput(form) {
    if (this.carriers.has(form)) return this.carriers.get(form)

    const carrier = document.createElement("input")
    carrier.type = "file"
    carrier.name = this.fieldNameValue
    carrier.multiple = true
    carrier.hidden = true
    form.appendChild(carrier)
    this.carriers.set(form, carrier)

    return carrier
  }
}
