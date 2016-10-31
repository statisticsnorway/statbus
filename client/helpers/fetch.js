import 'whatwg-fetch'

export default (
  url = `/api/${window.location.pathname}`,
  urlParams = {},
  method = 'get',
  body = {},
  onSuccess = f => f,
  onFail = f => f,
  onError = f => f
) => {
  fetch(
    url + Object.keys(params).reduce(
      (prev, cur) => prev + (cur
        ? `${prev ? '&' : '?'}${cur}=${params[cur]}`
        : ''),
      ''
    ),
    {
      body: JSON.stringify(body),
      credentials: 'same-origin',
      headers: { 'ContentType': 'application/json' },
      method,
    }
  ).then(
    ({ status, ...response }) => {
      if (status >= 300) onFail(response)
      else if (status >= 200) onSuccess(response)
    }
  ).catch(
    (error) => { onError(error) }
  )
}
