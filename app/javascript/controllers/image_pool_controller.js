import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "item"]
  static values = { reorderUrl: String }

  connect() {
    this.draggedItem = null
  }

  dragstart(event) {
    this.draggedItem = event.currentTarget
    event.currentTarget.classList.add("opacity-50")
  }

  dragend(event) {
    event.currentTarget.classList.remove("opacity-50")
    this.draggedItem = null
    this.saveOrder()
  }

  dragover(event) {
    event.preventDefault()
    const target = event.currentTarget
    if (!this.draggedItem || target === this.draggedItem) return

    const list = this.listTarget
    const items = [...this.itemTargets]
    const draggedIndex = items.indexOf(this.draggedItem)
    const targetIndex = items.indexOf(target)

    if (draggedIndex < targetIndex) {
      list.insertBefore(this.draggedItem, target.nextSibling)
    } else {
      list.insertBefore(this.draggedItem, target)
    }
  }

  moveUp(event) {
    event.preventDefault()
    const item = event.currentTarget.closest("[data-image-pool-target='item']")
    const previous = item.previousElementSibling
    if (previous) {
      this.listTarget.insertBefore(item, previous)
      this.saveOrder()
    }
  }

  moveDown(event) {
    event.preventDefault()
    const item = event.currentTarget.closest("[data-image-pool-target='item']")
    const next = item.nextElementSibling
    if (next) {
      this.listTarget.insertBefore(next, item)
      this.saveOrder()
    }
  }

  saveOrder() {
    const orderedIds = this.itemTargets.map((item) => item.dataset.imageId)
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.reorderUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ ordered_ids: orderedIds })
    }).catch((error) => {
      console.error("Failed to reorder images:", error)
    })
  }
}
