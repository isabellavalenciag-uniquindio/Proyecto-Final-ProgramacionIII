import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const Hooks = {
  FocusFirst: {
    mounted() {
      requestAnimationFrame(() => (this.el.querySelector("input:not([type=hidden]), select, textarea") || this.el.querySelector("button"))?.focus())
      this.previousFocus = document.activeElement
      this.keydown = (event) => {
        if (event.key !== "Tab") return
        const controls = [...this.el.querySelectorAll("button, input:not([type=hidden]), select, textarea, a[href]")]
          .filter(el => !el.disabled && el.offsetParent !== null)
        const first = controls[0], last = controls[controls.length - 1]
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault(); last?.focus()
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault(); first?.focus()
        }
      }
      this.el.addEventListener("keydown", this.keydown)
    },
    destroyed() {
      this.el.removeEventListener("keydown", this.keydown)
      this.previousFocus?.focus?.()
    }
  },
  Clock: {
    mounted() {
      const update = () => {
        this.el.textContent = new Intl.DateTimeFormat("es-CO", {
          hour: "2-digit", minute: "2-digit", timeZone: "America/Bogota", hour12: false
        }).format(new Date())
      }
      update()
      this.timer = setInterval(update, 30000)
    },
    destroyed() { clearInterval(this.timer) }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").content
const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
  longPollFallbackMs: undefined
})
liveSocket.connect()
window.addEventListener("phx:page-loading-start", () => document.documentElement.classList.add("page-loading"))
window.addEventListener("phx:page-loading-stop", () => document.documentElement.classList.remove("page-loading"))
