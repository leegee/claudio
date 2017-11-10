var EC = protractor.ExpectedConditions;

var Page = function (options) {
    Object.keys(Page.defaults).forEach((i) => {
        this[i] = options[i] || Page.defaults[i];
    });
    browser.waitForAngularEnabled(false);
    Object.seal(this);
};

Page.defaults = {
    baseUrl: 'http://localhost',
    url: '/index.html',
    username: null,
    passphrase: null
};

Page.prototype.load = function () {
    var url = this.baseUrl.concat( this.url );
    console.info('HTTP GET ', url);
    return browser.get(url);
};

/**
  * Uses the dreaded `sleep` method because finding the password
  * by any css selector tried fails.
  * @param {string} username - A Google username.
  * @param {string} passphrase - A Google passpharse.
  * @return {Promise.<void>} Promise resolved when logged in.
  */
Page.prototype.loginWithGoogle = function () {
    return this.selectWindowIndex(1)
      .then(() => {
        return browser.driver.findElement(by.css('[type="email"]'))
    }).then((el) => {
        el.sendKeys(this.username + protractor.Key.ENTER);
    }).then(() => {
        browser.driver.sleep(1000);
    }).then(() => {
        browser.actions().sendKeys(this.passphrase + protractor.Key.ENTER).perform();
    }).then(() => {
        browser.driver.sleep(10000);
    }).then(() => {
        this.selectWindowIndex(0);
    });
};

/**
* Focus the browser to the specified  window.
* [Implementation by and thanks to]{@link http://stackoverflow.com/questions/21700162/protractor-e2e-testing-error-object-object-object-has-no-method-getwindowha}
* @param  {Number} index The 0-based index of the window (eg 0=main, 1=popup)
* @return {webdriver.promise.Promise.<void>} Promise resolved when the index window is focused.
*/
Page.prototype.selectWindowIndex = (index) => {
    browser.driver.wait(function () {
        return browser.driver.getAllWindowHandles().then((handles) => {
            if (handles.length > index) {
                return true;
            }
        });
    });

    return browser.driver.getAllWindowHandles().then((handles) => {
        return browser.driver.switchTo().window(handles[index]);
    });
};

Page.prototype.canSignIn = function () {
    browser.wait(EC.elementToBeClickable($('#auth-button')), 5000);
    browser.driver.findElement(by.id('auth-button')).then(el => {
        el.click();
    }).then(() => {
        this.loginWithGoogle();
    // }).then(() => {
    //     expect(browser.driver.findElement(by.id('status'))).not.toBe(null);
    })
};

module.exports = Page;
