// Theme before the first paint, so the window never flashes
(function () {
  var preference = "system";
  try {
    preference = JSON.parse(localStorage.getItem("lambek.theme")) || "system";
  } catch (error) {
    preference = "system";
  }
  var dark = preference === "dark" || (preference === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
})();
