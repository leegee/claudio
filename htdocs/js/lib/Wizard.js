const Handlebars = require('Handlebars');

/**
 * Pages are `script` elements of `type` `text/handlebars`,
 *  with a `id` attribute.
 *
 * @example
 *  <script type=<script type='text/handlebars' id='manual-auth'> ...
 *
 * Pages are displayed via `Wizard.nextPage(:pageName)`.
 *
 * ## Data for Page Templates
 *
 * The Wizard supplies itself as `wizard`.
 *
 * ## Linking Within Pages
 *
 * Before templates are displayed, hyperlinks are added to any element that has an attribute
 * `data-goto-page`: the attribute's value can be a page name.
 *
 * ## Code For Pages
 *
 * Before a page is rendered, the Wizard will try to call a function with a camel-cased version
 * of the ant-cased page name, prefixed with the word 'page'.
 *
 * @example
 *  <script type=<script type='text/handlebars' id='manual-auth'> ...
 *  function pageManualAuth () { ...
 *
 * After a page is displayed, the Wizard will try to call a function with the same name, and the
 * suffix 'AfterRender`:
 *
 *  function pageManualAuthAfterRender () { ...
 *
 * Note that a suffix `BeforeRender` may be added to the function called before the page is rendered.
 *
 *  function pageManualAuthBeforeRender () { ...
 *
 * All three functions are called in the context of the Wizard.
 *
 * Yeah, @decorators would be nice without trainspoiling.
 *
 */
var Wizard = function (state) {
    this.state = {};
    // pageName: null,
    // lastPageName: null
    Object.keys(state).forEach((key) => {
        this.state[key] = state[key];
    });
    this.namespace = this.state.namespace;
    delete this.namesapce;

    this.pageEl = null;
    this.el = {
        main: document.getElementById('main'),
        footer: document.getElementById('footer'),
        ctrlMenu: document.getElementById('ctrl-menu'),
        ctrlNext: document.getElementById('ctrl-next'),
        ctrlBack: document.getElementById('ctrl-back'),
        ctrlCancel: document.getElementById('ctrl-cancel'),
        spinner: document.getElementById('spinner'),
    };
    this.hide('spinner');
    this.el.ctrlMenu.addEventListener('click', () => {
        this.nextPage('menu');
    });
    this.el.main.setAttribute('style', 'display:block"');

    // if (window.history.state && window.history.state.pageName) {
    //     this.state = window.history.state;
    //     this.nextPage(this.state.pageName);
    // }
    // window.onpopstate = (e) => {
    //     if (e.state) this.state = e.state;
    //     this.nextPage(this.state.pageName);
    //     console.info('>>>>>>>>>>>>> Location: ', document.location);
    //     console.info('>>>>>>>>>>>>> State: ', e.state);
    // }
}

Wizard.prototype.callAsMethod = function (method, ...args) {
    if (typeof method === 'string') {
        method = this.namespace[method];
    }
    return method.apply(this, args);
}

Wizard.prototype.nextPage = async function (pageName, ...passOnArgs) {
    if (this.state.lastPageName) {
        await this._execute('page-' + this.state.pageName + '-on-leave', passOnArgs);
    }

    // If not told where to go, check the current template for instructions
    if (!pageName && this.pageEl.nextPageName) {
        pageName = this.pageEl.nextPageName;
        console.log('Got next-page pageName from data-next-page: ', pageName);
    }

    this.pageEl = document.querySelector('script[type="text/handlebars"][id="' + pageName + '"]');
    if (!this.pageEl) {
        this.el.main.innerHTML = '<h2>Error</h2><p>Could not find the requested page, ' + pageName + '</p>';
        return;
    }

    this.state.nextPageName = this.pageEl.dataset.nextPage || null;
    this.state.pageName = pageName;

    var fnNames = [
        'page-' + this.state.pageName,
        'page-' + this.state.pageName + '-before-render'
    ];

    await this._execute(fnNames, passOnArgs);

    if (this.state.pageName === 'menu') {
        this.hide('footer');
    } else {
        this.show('footer');
    }

    this.render();

    if (this.state.pageName) {
        await this._execute('page-' + this.state.pageName + '-after-render', passOnArgs);
    }

    this.state.lastPageName = this.state.pageName;

    // window.location.hash = this.state.pageName;
    // window.history.pushState(this.state, 'Page ' + this.state.pageName, window.location.toString());

    console.log('Leave nextPage with page = ', this.state.pageName);
}

Wizard.prototype._execute = async function (fns, passOnArgs) {
    console.log('Wizard._execute', fns);
    if (!fns) return;
    let $name = this.namespace || window;
    let promises = [];
    if (typeof fns === 'string') fns = [fns];

    for (let f of fns) {
        var fn = this._antsToCamelCase(f);
        console.log('Look for ', fn);
        if (typeof $name[fn] === 'function') {
            console.log('Found %s, calling....', fn);
            promises.push($name[fn].call(this, passOnArgs));
            console.log('...called  %s', fn);
        } else {
            console.log('Did not find ', fn);
        }
    }
    if (promises) {
        console.log('Waiting on ', promises.length, promises);
        await Promise.all(promises);
        console.log('Done all promises');
    }
    else {
        console.log('Leave now');
        return Promise.resolve();
    }
};

// {{#wizardIncludeTemplate "publish-tables-and-skus"}}{{/wizardIncludeTemplate}}
Handlebars.registerHelper('wizardIncludeTemplate', function (templateId) {
    var html = Handlebars.compile(
        document.getElementById(templateId).innerHTML.toString()
    )(
        { wizard: this.wizard }
        );
    return new Handlebars.SafeString(html);
});

Wizard.prototype.render = function () {
    console.log('Enter render');
    try {
        // No caching:
        this.el.main.innerHTML = Handlebars.compile(
            this.pageEl.innerHTML.toString()
        )(
            { wizard: this }
            );
        window.scrollTo(0, 0);
        var links = document.querySelectorAll('[data-goto-page]');
        for (var el of links) {
            el.setAttribute('style',
                el.getAttribute('style') + ';cursor:pointer;'
            );
            el.onclick = async (e) => {
                this.show('spinner');
                await this.nextPage(e.target.dataset.gotoPage, e);
                this.hide('spinner');
            };
        };
    } catch (e) {
        console.error(e);
    }
};

Wizard.prototype.show = function (id) {
    this.el[id].setAttribute('style', 'display: block');
};

Wizard.prototype.hide = function (id) {
    this.el[id].setAttribute('style', 'display: none');
};

Wizard.prototype._antsToCamelCase = function (str) {
    return str.replace(/-(\w)/g, (_, initial) => {
        return initial.toUpperCase();
    });
};


module.exports = Wizard;