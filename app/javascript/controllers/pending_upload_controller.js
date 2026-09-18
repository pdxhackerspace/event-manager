import { Controller } from "@hotwired/stimulus"

// The image pool upload sits in its own form so "Add to Pool" can upload right
// away, which makes it easy to pick files and then save the event without ever
// clicking Add. This copies any still-unsent selection into the event form so
// saving the event uploads them too.
export default class extends Controller {
  static targets = ["input", "notice"]
  static values = { formId: String, fieldName: String }

  connect() {
    this.form = document.getElementById(this.formIdValue)
    if (!this.form) return

    this.transfer = this.transfer.bind(this)
    this.form.addEventListener("submit", this.transfer)
  }

  disconnect() {
    if (this.form) this.form.removeEventListener("submit", this.transfer)
    if (this.carrier) this.carrier.remove()
    this.carrier = null
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

  transfer() {
    const files = this.selectedFiles()
    if (files.length === 0) return

    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    this.carrierInput().files = transfer.files
  }

  selectedFiles() {
    if (!this.hasInputTarget || !this.inputTarget.files) return []

    return Array.from(this.inputTarget.files)
  }

  carrierInput() {
    if (this.carrier) return this.carrier

    this.carrier = document.createElement("input")
    this.carrier.type = "file"
    this.carrier.name = this.fieldNameValue
    this.carrier.multiple = true
    this.carrier.hidden = true
    this.form.appendChild(this.carrier)

    return this.carrier
  }
}
