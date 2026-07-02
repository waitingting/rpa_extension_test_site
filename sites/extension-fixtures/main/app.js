(function () {
  var canvas = document.getElementById("fixture-canvas");
  if (canvas && canvas.getContext) {
    var ctx = canvas.getContext("2d");
    ctx.fillStyle = "#f6fff8";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#2a9d8f";
    ctx.fillRect(16, 18, 64, 42);
    ctx.fillStyle = "#264653";
    ctx.font = "16px Segoe UI";
    ctx.fillText("Canvas", 92, 45);
  }

  var openDialog = document.getElementById("open-dialog");
  var closeDialog = document.getElementById("close-dialog");
  var dialog = document.getElementById("fixture-dialog");
  if (openDialog && dialog) {
    openDialog.addEventListener("click", function () {
      if (dialog.showModal) {
        dialog.showModal();
      } else {
        dialog.setAttribute("open", "open");
      }
    });
  }
  if (closeDialog && dialog) {
    closeDialog.addEventListener("click", function () {
      if (dialog.close) {
        dialog.close();
      } else {
        dialog.removeAttribute("open");
      }
    });
  }

  var shadowHost = document.getElementById("shadow-host");
  if (shadowHost && shadowHost.attachShadow) {
    var shadow = shadowHost.attachShadow({ mode: "open" });
    shadow.innerHTML = [
      "<style>",
      ".shadow-card{border:1px solid #8ab17d;border-radius:6px;padding:10px;background:#f7fff3}",
      "button{border:1px solid #52734d;border-radius:6px;background:white;padding:6px 10px}",
      "</style>",
      "<div id=\"shadow-card\" class=\"shadow-card\">",
      "<label>Shadow input <input id=\"shadow-input\" value=\"inside shadow\"></label>",
      "<button id=\"shadow-button\" type=\"button\">Shadow Button</button>",
      "</div>"
    ].join("");
  }

  var dynamicList = document.getElementById("dynamic-list");
  var addRow = document.getElementById("add-row");
  var removeRow = document.getElementById("remove-row");
  var count = 0;

  function appendRow() {
    count += 1;
    var row = document.createElement("div");
    row.className = "dynamic-row";
    row.id = "dynamic-row-" + count;
    row.innerHTML = [
      "<span>Dynamic row " + count + "</span>",
      "<input id=\"dynamic-input-" + count + "\" value=\"value " + count + "\">",
      "<button id=\"dynamic-button-" + count + "\" type=\"button\">Row Action</button>"
    ].join("");
    dynamicList.appendChild(row);
  }

  if (addRow) {
    addRow.addEventListener("click", appendRow);
  }
  if (removeRow) {
    removeRow.addEventListener("click", function () {
      if (dynamicList.lastElementChild) {
        dynamicList.removeChild(dynamicList.lastElementChild);
      }
    });
  }
  appendRow();
})();
