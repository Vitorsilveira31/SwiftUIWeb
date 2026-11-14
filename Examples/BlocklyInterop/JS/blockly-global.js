import * as Blockly from "blockly/core";
import "blockly/blocks";
import * as BrazilianPortuguese from "blockly/msg/pt-br";

Blockly.setLocale(BrazilianPortuguese);

function mount(_host, root, emit, initialStatus) {
  Blockly.Css.inject(root, true, "./media");

  const style = document.createElement("style");
  style.textContent = `
    :host { display:block; width:100%; height:100%; min-height:420px; }
    .blockly-shell { height:100%; min-height:420px; display:flex; flex-direction:column; gap:8px; }
    .blockly-status { margin:0; color:#475569; font:600 13px system-ui,sans-serif; }
    .blockly-editor { flex:1; min-height:380px; border:1px solid #cbd5e1; border-radius:10px; overflow:hidden; }
  `;
  root.append(style);

  const shell = document.createElement("section");
  shell.className = "blockly-shell";
  const status = document.createElement("p");
  status.className = "blockly-status";
  status.dataset.swiftLabel = "true";
  status.textContent = initialStatus;
  const editor = document.createElement("div");
  editor.className = "blockly-editor";
  shell.append(status, editor);
  root.append(shell);

  const toolbox = {
    kind: "categoryToolbox",
    contents: [
      { kind: "category", name: "Lógica", categorystyle: "logic_category", contents: [
        { kind: "block", type: "controls_if" }, { kind: "block", type: "logic_compare" },
        { kind: "block", type: "logic_boolean" }
      ] },
      { kind: "category", name: "Texto", categorystyle: "text_category", contents: [
        { kind: "block", type: "text" }, { kind: "block", type: "text_print" }
      ] },
      { kind: "category", name: "Matemática", categorystyle: "math_category", contents: [
        { kind: "block", type: "math_number" }, { kind: "block", type: "math_arithmetic" }
      ] }
    ]
  };
  const workspace = Blockly.inject(editor, {
    toolbox,
    css: false,
    trashcan: true,
    sounds: false,
    move: { scrollbars: true, drag: true, wheel: true },
    zoom: { controls: true, wheel: true }
  });
  const starter = workspace.newBlock("controls_if");
  starter.initSvg();
  starter.render();
  const onChange = event => {
    if (event.isUiEvent) return;
    emit(JSON.stringify(Blockly.serialization.workspaces.save(workspace)));
  };
  workspace.addChangeListener(onChange);

  return {
    workspace,
    status,
    updateCount: 0,
    dispose() {
      workspace.removeChangeListener(onChange);
      workspace.dispose();
      shell.remove();
      style.remove();
    }
  };
}

function update(instance, status) {
  instance.status.textContent = status;
  instance.updateCount += 1;
}

function dispose(instance) {
  instance.dispose();
}

// Registered with the page, not evaluated from Swift. This file is a module in Resources/head.html, which runs before the
// framework starts, so the definition goes through the queue (Documentation/BROWSER_APP_SHELL.md).
(globalThis.SwiftUIWebDOMComponents ??= { queue: [], define(name, factory) { this.queue.push([name, factory]); } })
  .define("blockly", () => ({ mount, update, dispose }));
