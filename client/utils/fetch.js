import fetch from 'whatwg-fetch'

export const get = (...params) => fetch(...params)
export const post = params => fetch(...params)
