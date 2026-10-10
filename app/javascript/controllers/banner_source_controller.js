import { Controller } from "@hotwired/stimulus"

// Picking a pool image or a file is a choice of banner source, so select the
// matching source radio; otherwise the form still submits "inherit".
export default class extends Controller {
  static targets = ["pool", "upload"]

  selectPool() {
    if (this.hasPoolTarget) this.poolTarget.checked = true
  }

  selectUpload(event) {
    if (this.hasUploadTarget && event.target.files.length > 0) this.uploadTarget.checked = true
  }
}
