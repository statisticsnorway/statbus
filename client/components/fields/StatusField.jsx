import React, { useState, useEffect, useCallback } from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'
import { getNewName } from '../../helpers/locale'

import styles from './styles.pcss'

const notSelected = { value: undefined, text: 'NotSelected' }

const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: getNewName(x),
  }),
  // eslint-disable-next-line react/prop-types
  render: params => (
    <div className="content">
      <div className="title">
        {params.code && <div className={styles['select-field-code']}>{params.code}</div>}
        {params.code && <br />}
        {getNewName(params, false)}
        <hr />
      </div>
    </div>
  ),
}

// eslint-disable-next-line react/prop-types
const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

// eslint-disable-next-line react/prop-types
const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(notSelected.text) : label}
    </span>
  </div>
)

const numOrStr = oneOfType([number, string])

function StatusField(props) {
  const [initialValue, setInitialValue] = useState(props.multiselect ? [] : null)
  const [value, setValue] = useState(hasValue(props.value) ? props.value : props.multiselect ? [] : notSelected.value)
  const [optionsFetched, setOptionsFetched] = useState(false)
  const [options, setOptions] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const loadOptions = useCallback(() => {
    if (isLoading) return

    internalRequest({
      url: `/api/lookup/paginated/${props.lookup}`,
      queryParams: { page, pageSize: props.pageSize, wildcard },
      method: 'get',
      onSuccess: (data) => {
        let updatedOptions = [...data]

        if (props.responseToOption) updatedOptions = updatedOptions.map(props.responseToOption)
        setOptions(prevOptions => [...prevOptions, ...updatedOptions])
        setPage(prevPage => prevPage + 1)
      },
    })
  }, [isLoading, props.lookup, page, props.pageSize, wildcard, props.responseToOption])

  const handleLoadOptions = debounce(loadOptions, props.waitTime)

  const handleAsyncSelect = (data) => {
    const { multiselect, onChange, responseToOption } = props
    const raw = data !== null ? data : { value: notSelected.value }
    const newValue = multiselect ? raw.map(x => x.value) : raw.value

    if (!R.equals(value, newValue)) {
      setValue(multiselect ? raw.map(responseToOption) : responseToOption(raw), () =>
        onChange(undefined, { ...props, value: newValue }, data))
    }
  }

  const handlePlainSelect = (event, { value, ...data }) => {
    const nextData = { ...data, ...props, value }
    if (!R.equals(value, value)) {
      setValue(value, () => props.onChange(event, nextData))
    }
  }

  const handleInputChange = (newValue) => {
    if (newValue && props.lookup !== null) {
      setIsLoading(true)

      internalRequest({
        url: `/api/lookup/paginated/${props.lookup}`,
        queryParams: { page: 0, pageSize: props.pageSize, wildcard: newValue },
        method: 'get',
        onSuccess: (data) => {
          let updatedOptions = [...data]

          if (props.responseToOption) updatedOptions = updatedOptions.map(props.responseToOption)
          setOptions(updatedOptions)
          setPage(0)
          setIsLoading(false)
        },
      })
    }
  }

  useEffect(() => {
    if (hasValue(props.options)) return

    const { value: ids, lookup, multiselect, responseToOption } = props
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (data) => {
        if (hasValue(data)) {
          setValue(multiselect ? data.map(responseToOption) : responseToOption(data[0]))
          setInitialValue(multiselect ? data.map(responseToOption) : responseToOption(data[0]))
        }
      },
    })

    fetch(`/api/lookup/paginated/${lookup}?page=0&pageSize=10`, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
    })
      .then(resp => resp.json())
      .then((result) => {
        const updatedOptions =
          Array.isArray(result) && result.length > 0 ? result.map(props.responseToOption) : []
        setOptions(updatedOptions)
        setIsLoading(false)
        setPage(prevPage => prevPage + 1)
      })
  }, [props])

  useEffect(() => {
    const { locale, multiselect, responseToOption, isEdit } = props
    const { value, initialValue } = props
    const ids =
      isEdit && R.is(Array, props.value)
        ? R.is(Array, initialValue) && initialValue.map(x => x.id)
        : initialValue && initialValue.id

    if (isEdit && R.equals(ids, props.value)) {
      setValue(initialValue)
    }

    if (!R.equals(props.value && value)) {
      setValue(props.value)
    }

    if (props.value === 0 || props.value.length === 0 || props.value[0] === 0) {
      setValue('')
    }

    if (props.locale !== locale) {
      setValue(multiselect ? value.map(responseToOption) : responseToOption(value), () => {
        setOptions(prevOptions => prevOptions.map(responseToOption))
      })
    }
  }, [props])

  useEffect(() => {
    setInitialValue(props.value)
  }, [props.value])

  useEffect(() => {
    handleLoadOptions.cancel()
  }, [])

  const hasErrors =
    (props.touched && hasValue(props.errors)) || (props.error && hasValue(props.errors))
  const label = props.label !== undefined ? props.localize(props.label) : undefined
  const title = props.title ? props.localize(props.title) : label
  const placeholder = props.placeholder ? props.localize(props.placeholder) : label
  const hasOptions = hasValue(options)
  const [Select, ownProps] = hasOptions
    ? [
      SemanticUiSelect,
      {
        onChange: handlePlainSelect,
        error: hasErrors,
        multiple: props.multiselect,
        options,
        required: props.required,
        title,
        inline: props.inline,
        width: props.width,
      },
    ]
    : [
      ReactSelect,
      {
        onChange: handleAsyncSelect,
        loadOptions: handleLoadOptions,
        valueComponent: props.multiselect
          ? createRemovableValueComponent(props.localize)
          : createValueComponent(props.localize),
        inputProps: { type: 'react-select', name: props.name },
        className: hasErrors ? 'react-select--error' : '',
        multi: props.multiselect,
        backspaceRemoves: true,
        searchable: true,
        pagination: true,
        isLoading,
        onMenuScrollToBottom: handleLoadOptions,
        onInputChange: handleInputChange,
      },
    ]
  const className = `field${!hasOptions && props.required ? ' required' : ''}`

  return (
    <div
      className={className}
      style={{ opacity: `${props.disabled ? 0.25 : 1}` }}
      data-tooltip={props.popuplocalizedKey ? props.localize(props.popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={props.name}>{label}</label>}
      <Select
        {...ownProps}
        value={value}
        options={options}
        onBlur={props.onBlur}
        name={props.name}
        placeholder={placeholder}
        disabled={props.disabled}
        openOnFocus
      />
      {hasErrors && (
        <Message title={label} list={props.errors.map(props.localize)} compact={hasOptions} error />
      )}
    </div>
  )
}

StatusField.propTypes = {
  name: string.isRequired,
  value: createPropType(props => (props.multiselect ? arrayOf(numOrStr) : numOrStr)),
  onChange: func.isRequired,
  onBlur: func,
  errors: arrayOf(string),
  label: string,
  title: string,
  placeholder: string,
  multiselect: bool,
  required: bool,
  touched: bool,
  disabled: bool,
  inline: bool,
  width: numOrStr,
  createOptionComponent: func,
  localize: func.isRequired,
  locale: string.isRequired,
  popuplocalizedKey: string,
  pageSize: number,
  waitTime: number,
  lookup: number,
  responseToOption: func,
  options: arrayOf(shape({
    value: numOrStr.isRequired,
    text: numOrStr.isRequired,
  })),
}

StatusField.defaultProps = {
  value: null,
  onBlur: R.identity,
  label: null,
  title: null,
  placeholder: null,
  multiselect: false,
  required: false,
  errors: [],
  disabled: false,
  inline: false,
  width: null,
  createOptionComponent: NameCodeOption.render,
  pageSize: 10,
  waitTime: 250,
  lookup: null,
  responseToOption: NameCodeOption.transform,
  options: null,
  touched: false,
  popuplocalizedKey: null,
}

export default StatusField
