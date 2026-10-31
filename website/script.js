"use strict";

// All interaction stays in this page. No requests, identifiers, or saved preferences.
const keyboard = document.querySelector("#keyboard-grid");
const rows = [
  ["esc", "◌", "☀", "▦", "⌕", "◐", "◁", "▷", "▷▷", "◖", "◀", "●"],
  ["tab", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "⌫"],
  ["⇧", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "↵"],
  ["fn", "⌃", "⌥", "⌘", "space", "⌥", "←"],
];
rows.forEach((row) => row.forEach((label) => {
  const key = document.createElement("span");
  key.className = label === "space" ? "key space" : "key";
  key.textContent = label === "space" ? "" : label;
  keyboard.append(key);
}));

const moments = {
  day: { time: "Before sunset", brightness: "Backlight off", context: "Daylight takes care of the keys." },
  evening: { time: "After sunset", brightness: "Backlight at 50%", context: "Your chosen nighttime level." },
  away: { time: "Idle for 30 seconds", brightness: "Backlight off", context: "Resumes on input, following the current mode." },
};
document.querySelectorAll("[data-demo]").forEach((button) => {
  button.addEventListener("click", () => {
    const mode = button.dataset.demo;
    const moment = moments[mode];
    document.querySelector(".day-demo").dataset.mode = mode;
    document.querySelector("#demo-time").textContent = moment.time;
    document.querySelector("#demo-brightness").textContent = moment.brightness;
    document.querySelector("#demo-context").textContent = moment.context;
    document.querySelectorAll("[data-demo]").forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
  });
});

const tours = {
  system: {
    label: "System Control", image: "app-system.png", width: 760, height: 830,
    title: "Choose the light you like.",
    description: "Set a fixed brightness in 2% steps, or switch on Auto-Brightness to follow your Mac’s ambient light sensor.",
    detail: "Quick brightness previews last three seconds, then your current mode resumes.",
    alt: "Actual System Control panel with a 50 percent brightness slider and Auto-Brightness switch.",
  },
  solar: {
    label: "Sun Cycle", image: "app-sun-cycle.png", width: 760, height: 1252,
    title: "Let sunset be the switch.",
    description: "Choose a night brightness and a location. Lumina calculates sunrise and sunset on your Mac, with no online solar service.",
    detail: "Use manual coordinates offline or request Mac Location. This screenshot uses example Berlin coordinates, not a personal location.",
    alt: "Actual Sun Cycle panel with sample sunrise at 6:59, sunset at 16:40, and 50 percent night brightness.",
  },
  slots: {
    label: "Time Slots", image: "app-time-slots.png", width: 760, height: 1252,
    title: "Give your routine a little structure.",
    description: "Create up to three daily slots with their own brightness and optional ambient setting. Overnight slots work across midnight; outside your slots, the backlight is off.",
    detail: "This example uses 50% from 18:00–22:00, then 30% from 22:00–01:00. Location access isn’t needed.",
    alt: "Actual Time Slots panel showing Evening focus, 18:00–22:00 at 50 percent, and Late reading, 22:00–01:00 at 30 percent.",
  },
  idle: {
    label: "Inactivity Timeout", image: "app-idle.png", width: 760, height: 950,
    title: "Leave the desk. Leave the light to Lumina.",
    description: "Choose minutes and seconds from native menus. When you stop using your Mac for that long, the keyboard lighting turns off until input resumes.",
    detail: "A nonzero slot timeout takes priority over the global timer. Set a slot to 00:00 to use the global setting instead.",
    alt: "Actual System Control panel with Inactivity Timeout enabled at zero minutes and thirty seconds.",
  },
};
const tabs = Array.from(document.querySelectorAll("[data-tour]"));
function selectTour(tab) {
  const tour = tours[tab.dataset.tour];
  tabs.forEach((item) => {
    item.setAttribute("aria-selected", String(item === tab));
    item.tabIndex = item === tab ? 0 : -1;
  });
  document.querySelector("#tour-panel").setAttribute("aria-labelledby", tab.id);
  document.querySelector("#tour-title").textContent = tour.title;
  document.querySelector("#tour-description").textContent = tour.description;
  document.querySelector("#tour-detail").textContent = tour.detail;
  const image = document.querySelector("#tour-image");
  image.src = `assets/${tour.image}`;
  image.alt = tour.alt;
  image.width = tour.width;
  image.height = tour.height;
  const link = document.querySelector("#tour-image-link");
  link.href = image.src;
  link.dataset.screenshot = tour.label;
  document.querySelector("#tour-caption").textContent = `Actual app screenshot · ${tour.label} · Sample settings`;
}
tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectTour(tab));
  tab.addEventListener("keydown", (event) => {
    let target;
    if (event.key === "ArrowRight" || event.key === "ArrowDown") target = tabs[(index + 1) % tabs.length];
    if (event.key === "ArrowLeft" || event.key === "ArrowUp") target = tabs[(index - 1 + tabs.length) % tabs.length];
    if (event.key === "Home") target = tabs[0];
    if (event.key === "End") target = tabs[tabs.length - 1];
    if (target) { event.preventDefault(); selectTour(target); target.focus(); }
  });
});

const dialog = document.querySelector("#screenshot-dialog");
document.querySelectorAll("[data-screenshot]").forEach((link) => {
  link.addEventListener("click", (event) => {
    if (event.ctrlKey || event.metaKey || event.shiftKey || typeof dialog.showModal !== "function") return;
    event.preventDefault();
    const image = document.querySelector("#dialog-image");
    image.src = link.href;
    image.alt = link.querySelector("img").alt;
    document.querySelector("#screenshot-dialog-title").textContent = link.dataset.screenshot;
    dialog.showModal();
  });
});
document.querySelector("#close-screenshot").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
