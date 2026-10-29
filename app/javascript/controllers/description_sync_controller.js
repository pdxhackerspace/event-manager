import { Controller } from "@hotwired/stimulus"

// Keeps the plain-text description in step with the HTML editor while the
// "Keep in sync" box is checked. The server repeats this conversion on save;
// this copy is only so the plain-text field updates while typing.
export default class extends Controller {
  static targets = ["bodyHtml", "bodyText", "sync"]

  connect() {
    this.form = this.element.closest("form")
    this.onSubmit = () => this.syncFromHtml()
    this.form?.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit)
  }

  syncFromHtml() {
    if (!this.shouldSync() || !this.hasBodyTextTarget) return
    // Without a live editor, an empty HTML field would erase plain text the
    // host already typed. The server keeps that text when the HTML is blank.
    if (!this.editorReady()) return

    this.bodyTextTarget.value = this.htmlToPlainText(this.currentHtml())
  }

  editorReady() {
    const textarea = this.bodyHtmlTarget
    return typeof tinymce !== "undefined" && textarea.id && tinymce.get(textarea.id)
  }

  shouldSync() {
    return !this.hasSyncTarget || this.syncTarget.checked
  }

  currentHtml() {
    const textarea = this.bodyHtmlTarget
    if (typeof tinymce !== "undefined" && textarea.id) {
      const editor = tinymce.get(textarea.id)
      if (editor) {
        editor.save()
        return editor.getContent()
      }
    }

    return textarea.value
  }

  htmlToPlainText(html) {
    const container = document.createElement("div")
    container.innerHTML = html || ""

    container.querySelectorAll("script, style").forEach((element) => element.remove())
    container.querySelectorAll("br").forEach((element) => element.replaceWith("\n"))

    container.querySelectorAll("li").forEach((element) => {
      if (element.textContent.trim().length > 0) element.prepend("- ")
    })

    container.querySelectorAll("p, li, blockquote, h1, h2, h3, h4, h5, h6").forEach((element) => {
      const urls = Array.from(element.querySelectorAll("a[href]"))
        .map((link) => link.getAttribute("href"))
        .filter((url) => url && url.trim().length > 0 && !element.textContent.includes(url))

      if (urls.length > 0) element.append(`\n\n${urls.join("\n")}\n`)
    })

    container.querySelectorAll("p, blockquote, h1, h2, h3, h4, h5, h6").forEach((element) => {
      element.append("\n\n")
    })

    container.querySelectorAll("div, li, tr, ul, ol").forEach((element) => {
      element.append("\n")
    })

    container.querySelectorAll("td, th").forEach((element) => {
      element.append(" ")
    })

    return container.textContent
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n[ \t]+/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim()
  }
}
