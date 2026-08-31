import { Controller } from "@hotwired/stimulus"

// Fills the ticket form from a preset (an eval case) chosen in the dropdown.
export default class extends Controller {
  static targets = ["select", "ticketId", "tier", "locale", "subject", "body"]
  static values = { presets: Array }

  apply() {
    const id = this.selectTarget.value
    if (!id) return
    const preset = this.presetsValue.find((p) => p.id === id)
    if (!preset) return
    const t = preset.ticket || {}
    this.ticketIdTarget.value = t.ticket_id || ""
    this.tierTarget.value = t.customer_tier || "standard"
    this.localeTarget.value = t.locale || "es-ES"
    this.subjectTarget.value = t.subject || ""
    this.bodyTarget.value = t.body || ""
  }
}
