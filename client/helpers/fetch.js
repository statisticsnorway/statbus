import 'whatwg-fetch'

export default ({
  url = `/api${window.location.pathname}`,
  urlParams = {},
  method = 'get',
  body,
  onSuccess = f => f,
  onFail = f => f,
  onError = f => f,
}) => {
  const fetchUrl = url + Object.keys(urlParams).reduce(
    (prev, cur) => prev + (cur
      ? `${prev ? '&' : '?'}${cur}=${urlParams[cur]}`
      : ''),
    ''
  )
  const fetchParams = {
    method,
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined,
    headers: method === 'put' || method === 'post'
      ? { 'Content-Type': 'application/json' }
      : undefined,
  }
  if (method === 'get' || method === 'post') {
    fetch(fetchUrl, fetchParams)
      .then(r => r.status < 300 ? r.json() : onFail(r))
      .then(onSuccess)
      .catch(onError)
  } else {
    fetch(fetchUrl, fetchParams)
      .then(r => r.status < 300 ? onSuccess(r) : onFail(r))
      .catch(onError)
  }
}
