module.exports.now = function (onload) {
    var script = document.createElement('script');
    script.setAttribute('src', 'https://apis.google.com/js/api.js');
    script.setAttribute('onload', onload);
    script.setAttribute('onreadystatechange', "if (this.readyState === 'complete') this.onload()");
    document.head.appendChild(script);
}
