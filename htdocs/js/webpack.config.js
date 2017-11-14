var path = require('path');
var webpack = require('webpack');

// mocha --compilers js:babel-core/register --require babel-polyfill

module.exports = {
    entry: ['babel-polyfill', './index.js'],
    output: {
        path: path.resolve(__dirname, 'build'),
        filename: 'main.bundle.js'
    },
    module: {
        loaders: [
            {
                test: /\.js$/,
                loader: 'babel-loader',
                exclude: /node_modules/,
                query: {
                    presets: ['es2015', 'stage-2']
                }
            }
        ]
    },
    devtool: 'eval-source-map',
    stats: {
        colors: false
    },
    node: {
        fs: 'empty'
    },
    watch: true,
    devtool: 'source-map'
};