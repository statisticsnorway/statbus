import 'whatwg-fetch'

export const get = (
  params = {},
  url = window.location.pathname,
  onSuccess = f => f,
  onFail = f => f,
  onError = f => f
) => {
  fetch(
    url + Object.keys(params).reduce(
      (prev, cur) => prev + (cur ? `${prev ? '&' : '?'}${cur}=${params[cur]}` : ''),
      ''
    ),
    { credentials: 'same-origin' }
  ).then(
    resp => resp.status >= 300
      ? onFail(resp)
      : resp.json()
  ).then(
    (data) => { onSuccess(data) }
  ).catch(
    (err) => { onError(err) }
  )
}

export const post = (
  body = {},
  url = window.location.pathname,
  onSuccess = f => f,
  onFail = f => f,
  onError = f => f
) => {
  fetch(
    url, {
      method: 'post',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
      body: JSON.stringify(body),
    }
  ).then(
    ({ status, ...resp }) => {
      if (status >= 300) onFail(resp)
      else if (status >= 200) onSuccess(resp)
    }
  ).catch(
    (err) => { onError(err) }
  )
}
