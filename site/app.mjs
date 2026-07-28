const dateNode = document.querySelector("#local-date");
const timeNode = document.querySelector("#local-time");
const launchByKey = new Map(
  [...document.querySelectorAll("[data-key]")]
    .map((link) => [link.dataset.key, link]),
);

function renderClock() {
  const now = new Date();
  dateNode.textContent = new Intl.DateTimeFormat(undefined, {
    weekday: "short",
    month: "short",
    day: "2-digit",
  }).format(now).toUpperCase();
  timeNode.textContent = new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).format(now);
}

document.addEventListener("keydown", (event) => {
  if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
    return;
  }
  const destination = launchByKey.get(event.key);
  if (destination) {
    destination.click();
  }
});

renderClock();
setInterval(renderClock, 1000);
