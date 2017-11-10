require('../.env.js');

var EC = protractor.ExpectedConditions;

var Page = require('./Page');

var page = new Page({
    browser: browser,
    username: process.env.IZEL_GMAIL_USER,
    passphrase: process.env.IZEL_GMAIL_PASS
});

describe('Map Uploader', () => {
    it('should have a title', () => {
        page.load();
        expect(browser.getTitle()).toEqual('Map Uploader');
    });

    it('signs in', () => {
        page.canSignIn();
    })

    // it('has status element', () => {
        // expect( browser.driver.findElement(by.id('status')).getText() ).not.toBe(null);
    // });

});


