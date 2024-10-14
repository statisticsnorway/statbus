/**
 * URLSearchParamsDict is a flexible type that represents potential inputs for URLSearchParams.
 * It can be a string, an object, an existing URLSearchParams instance, or undefined.
 * This flexibility allows for seamless transitions between server-side and client-side code,
 * ensuring that URLSearchParams are always properly instantiated when needed.
 */
export type URLSearchParamsDict = string | URLSearchParams | string[][] | Record<string, string> | undefined;

/**
 * IURLSearchParamsDict is an interface that encapsulates URLSearchParamsDict.
 * It is used to define props in components that require initial URL search parameters.
 * This interface enforces consistency and clarity in how URL search parameters are passed
 * and handled across different components.
 */
export interface IURLSearchParamsDict {
  readonly initialUrlSearchParamsDict: URLSearchParamsDict;
}

/**
 * toURLSearchParams is a utility function that ensures the input is converted into a URLSearchParams instance.
 * This function prevents runtime errors by guaranteeing that URLSearchParams methods can be safely called.
 * It provides a consistent way to handle URL search parameters, regardless of their initial form.
 *
 * @param params - The input parameters that need to be converted to URLSearchParams.
 * @returns A URLSearchParams instance.
 */
export function toURLSearchParams(params: URLSearchParamsDict): URLSearchParams {
  if (params instanceof URLSearchParams) {
    return params;
  }
  return new URLSearchParams(params);
}
