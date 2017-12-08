"use strict";

const Wizard = require('./lib/Wizard');
const LoadGoogle = require('./lib/LoadGoogle');
const Config = require('./Config');

LoadGoogle.now("window.ENTER()");

const izel = {};

window.ENTER = function () {
    console.log('ENTER');
    gapi.load('client:auth2', initClient);
};

function initClient() {
    console.log(Config);
    gapi.client.init({
        apiKey: Config.apiKey,
        discoveryDocs: Config.discoveryUrls,
        clientId: Config.clientId,
        scope: Config.scopes.join(' ')
    }).then(function () {
        document.getElementById('spinner').setAttribute('style', 'display:none');
        window.GoogleAuth = gapi.auth2.getAuthInstance();
        window.GoogleAuth.isSignedIn.listen(setSigninStatus);
        setSigninStatus();
        document.getElementById('auth-button').addEventListener('click', function () {
            window.GoogleAuth.isSignedIn.get() ? window.GoogleAuth.signOut() : window.GoogleAuth.signIn();
        });
    });
}

function setSigninStatus(isSignedIn) {
    var user = window.GoogleAuth.currentUser.get();
    var isAuthorized = user.hasGrantedScopes(Config.scopes.join(' '));
    var button = document.getElementById('auth-button');
    button.innerHTML = isAuthorized ? 'Sign out' : 'Sign In';
    button.disabled = false;
    if (isAuthorized) {
        window.wizard = new Wizard({
            namespace: izel,
            indexBaseDir: Config.indexBaseDir,
            indexJsDir: Config.indexBaseDir + new Date().toISOString().replace(/\W/g, '_') + '/',
            access_token: user.getAuthResponse().access_token
        });
        window.wizard.nextPage('menu');
    }
}

const authString = function (accessToken) {
    return 'key=' + Config.apiKey + '&access_token=' + accessToken;
};

izel.pageMenuAfterRender = function () {
    this.hide('footer');

    this.updateStatus = this.updateStatus || function () {
        fetch(Config.endpoints.local + '?action=status;' + authString(this.state.access_token)).then((res) => {
            return res.json();
        }).then((json) => {
            console.table(json);
            try {
                document.getElementById('number-of-mapped-skus').innerHTML = Number(json.numberOfMappedSkus).toLocaleString();
                document.getElementById('number-of-total-skus').innerHTML = Number(json.numberOfTotalSkus).toLocaleString();
            } catch (e) { }
        });
    }
    document.getElementById('status').addEventListener('click', () => {
        this.updateStatus();
    })
    this.updateStatus();
};

izel.pageSelectAugmentDbAfterRender = async function () {
    document.getElementById('skusCsvAugment').addEventListener('change', (e) => {
        this.state.file = e.target.files[0];
        this.nextPage('augment-db');
    }, false);
}

izel.pageSelectSkusAfterRender = async function () {
    document.getElementById('skusCsv').addEventListener('change', (e) => {
        this.state.file = e.target.files[0];
        this.nextPage('preview-upload');
    }, false);
}

izel.pageWipeGoogleDataAfterRender = async function () {
    if (confirm('Really wipe all Fusion Table data?')) {
        this.callAsMethod('cgi', {
            action: 'wipe-google-data',
            logWindowId: 'wipe-google-data-log'
        });
    } else {
        return this.nextPage('menu');
    }
};

izel.pageMapSomeSkusBeforeRender = async function () {
    this.state.skusToProcess = document.getElementById('skusToProcess').value;
};

izel.pageMapSomeSkusAfterRender = async function () {
    this.callAsMethod('cgi', {
        action: 'map-some-skus',
        'skus-text': this.state.skusToProcess,
        logWindowId: 'map-some-skus-log'
    });
};

izel.pageAugmentDbAfterRender = function () {
    this.callAsMethod('cgi', {
        action: 'augment-db',
        'skus-file': this.state.file,
        logWindowId: 'augment-db-log'
    })
};

izel.pageUploadDbAfterRender = function () {
    this.callAsMethod('cgi', {
        action: 'upload-db',
        'skus-file': this.state.file,
        logWindowId: 'upload-db-log'
    })
};

/**
* Before the cx closes, server will respond with HTML status updates.
*/
izel.cgi = async function (args) {
    return new Promise((resolve, reject) => {
        if (!args || !args.action || !args.logWindowId) {
            throw new Error('No args, action || logWindowId?');
        }

        console.log('Log to ', args.logWindowId);

        var buffer = '',
            data = new FormData(),
            logwindow = document.getElementById(args.logWindowId),
            request = new XMLHttpRequest(),
            show = (html) => {
                logwindow.innerHTML = html;
                logwindow.scrollTop = logwindow.scrollHeight + logwindow.clientHeight;
            }
            ;

        for (let key in args) {
            data.append(key, args[key]);
        }

        request.onreadystatechange = () => {
            if (request.responseText.length) {
                show(request.responseText);
            }
            if (request.readyState === XMLHttpRequest.DONE) {
                if (request.status === 200) {
                    if (args.nextPage) {
                        this.nextPage(args.nextPage, this.state.indexJsDir);
                    }
                    resolve();
                } else {
                    console.error(request);
                    reject(request.status);
                }
            }
        }
        request.open('POST', Config.endpoints.local + '?' + authString(this.state.access_token));
        request.send(data);
    });
}

izel.pagePreviewDbBeforeRender = async function () {
    var response = await window.fetch(
        Config.endpoints.local + '?action=preview-db'
    );
    var json = await response.json();
    this.callAsMethod('viewIndex', json);
};

izel.setCssClass = function (internalTableId, isPublished) {
    var style = document.createElement('style');
    style.type = 'text/css';
    document.getElementsByTagName('head')[0].appendChild(style);
    var str = 'FT_' + internalTableId + '::before { content: "'
        + (internalTableId === 0 ? '☑' : '☐')
        + '"}';
    style.sheet.insertRule(str, 0);
}

izel.pagePreviewDbAfterRender = async function () {
    var todo = 0;

    if (!todo) {
        var el = document.getElementById('publish-tableInternalId2googleTableId');
        el.outerHTML = '';
    }
}

izel.viewIndex = function (json) {
    Object.keys(json).forEach((key) => {
        this.state[key] = json[key];
    });
};
