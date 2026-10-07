// I timer dei worker non vengono rallentati quando la scheda è in background,
// a differenza di setInterval nella pagina: il monitor usa questi tick.
let timer = null;

self.onmessage = ({ data }) => {
  clearInterval(timer);
  timer = data > 0 ? setInterval(() => self.postMessage(0), data) : null;
};
