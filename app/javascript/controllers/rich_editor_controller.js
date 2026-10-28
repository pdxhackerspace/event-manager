import { Controller } from "@hotwired/stimulus"

// TinyMCE wrapper, adapted from member-zone's email template editor.
// The textarea stays in the form so a normal submit still posts the HTML.
export default class extends Controller {
  static targets = ["editor"]
  static values = {
    validElements: String,
    placeholder: String
  }

  connect() {
    this.beforeCache = () => this.removeEditor()
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.initEditor()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.removeEditor()
  }

  initEditor() {
    const textarea = this.editorTarget
    if (typeof tinymce === "undefined" || !textarea.id) return

    const existing = tinymce.get(textarea.id)
    if (existing) existing.remove()

    const dark = window.matchMedia("(prefers-color-scheme: dark)").matches
    const controller = this

    tinymce.init({
      target: textarea,
      height: 320,
      menubar: false,
      branding: false,
      promotion: false,
      plugins: "link lists code",
      toolbar: "undo redo | blocks | bold italic underline | bullist numlist | link | code",
      block_formats: "Paragraph=p; Heading 2=h2; Heading 3=h3; Heading 4=h4; Blockquote=blockquote",
      placeholder: this.placeholderValue || "",
      skin: dark ? "oxide-dark" : "oxide",
      content_css: dark ? "dark" : "default",
      content_style: "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; font-size: 16px; line-height: 1.5; }",
      valid_elements: this.validElementsValue,
      invalid_elements: "script,style,img,iframe,object,embed,form",
      convert_urls: false,
      relative_urls: false,
      remove_script_host: false,
      link_default_protocol: "https",
      link_target_list: false,
      link_title: false,
      setup(editor) {
        controller.editor = editor
        const syncTextarea = () => {
          editor.save()
          textarea.dispatchEvent(new CustomEvent("rich-editor:change", { bubbles: true }))
        }
        editor.on("change keyup undo redo setcontent", syncTextarea)
      },
      init_instance_callback(editor) {
        const form = textarea.closest("form")
        if (!form) return

        controller.onFormSubmit = () => editor.save()
        form.addEventListener("submit", controller.onFormSubmit)
      }
    })
  }

  removeEditor() {
    const textarea = this.hasEditorTarget ? this.editorTarget : null
    const form = textarea?.closest("form")
    if (form && this.onFormSubmit) form.removeEventListener("submit", this.onFormSubmit)

    if (this.editor) {
      this.editor.remove()
      this.editor = null
    }
  }
}
