import React, { useState, useEffect } from 'react'
import PropTypes, { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import * as R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation.js'
import { internalRequest } from 'helpers/request.js'
import { getNewName } from 'helpers/locale.js'

import styles from './styles.scss'

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

export function InstitutionalSectorCodeField(props) {
  const {
    name,
    value: initialValue,
    onChange,
    onBlur,
    errors: errorKeys,
    label: labelKey,
    title: titleKey,
    placeholder: placeholderKey,
    multiselect,
    required,
    touched,
    disabled,
    inline,
    width,
    createOptionComponent,
    localize,
    popuplocalizedKey,
    pageSize,
    waitTime,
    lookup,
    responseToOption,
    options,
  } = props

  const [value, setValue] = useState(initialValue)
  const [optionsFetched, setOptionsFetched] = useState(false)
  const [optionsState, setOptionsState] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const handleAsyncSelect = (data) => {
    const raw = data !== null ? data : { value: notSelected.value }
    const newValue = multiselect ? raw.map(x => x.value) : raw.value
    if (!R.equals(value, newValue)) {
      setValue(newValue)
      onChange(undefined, { ...props, value }, data)
    }
  }

  const handlePlainSelect = (event, { value: newValue, ...data }) => {
    const nextData = { ...data, ...props, value: newValue }
    if (!R.equals(value, newValue)) {
      setValue(newValue)
      onChange(event, nextData)
    }
  }

  const handleInputChange = (newValue) => {
    if (newValue && lookup !== null) {
      setIsLoading(true)
      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page: 0, pageSize, wildcard: newValue },
        method: 'get',
        onSuccess: (data) => {
          let newOptions = [...data]
          if (responseToOption) newOptions = newOptions.map(responseToOption)
          setOptionsState(optionsState.concat(newOptions))
          setPage(page + 1)
          setIsLoading(false)
        },
      })
    }
  }

  const loadOptions = () => {
    if (!isLoading) {
      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams: { page, pageSize, wildcard },
        method: 'get',
        onSuccess: (data) => {
          let newOptions = [...data]
          if (responseToOption) newOptions = newOptions.map(responseToOption)
          setOptionsState(optionsState.concat(newOptions))
          setPage(page + 1)
        },
      })
    }
  }

  const handleLoadOptions = debounce(loadOptions, waitTime)

  useEffect(() => {
    if (hasValue(options)) return

    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids: initialValue },
      method: 'get',
      onSuccess: (data) => {
        if (hasValue(data)) {
          setValue(multiselect ? data.map(responseToOption) : responseToOption(data[0]))
          props.onChange(undefined, { ...props, value: data })
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
        const newOptions =
          Array.isArray(result) && result.length > 0 ? result.map(responseToOption) : []
        setOptionsState(newOptions)
        setIsLoading(false)
        setPage(page + 1)
      })
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const ids =
      props.isEdit && R.is(Array, props.value)
        ? R.is(Array, initialValue) && initialValue.map(x => x.id)
        : initialValue && initialValue.id
    if (props.isEdit && R.equals(ids, props.value)) {
      setValue(initialValue)
    }
    if (!R.equals(props.value && value)) {
      setValue(props.value)
    }
    if (props.value === 0 || props.value.length === 0 || props.value[0] === 0) {
      setValue('')
    }
  }, [props.value])

  useEffect(() => {
    if (props.locale !== props.locale) {
      setValue(multiselect ? value.map(responseToOption) : responseToOption(value))
      setOptionsState(optionsState.map(responseToOption))
    }
  }, [props.locale])

  const hasErrors = touched && hasValue(errorKeys)
  const label = labelKey !== (undefined || null) ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label
  const hasOptions = hasValue(options)

  const Select = hasOptions ? SemanticUiSelect : ReactSelect

  const ownProps = hasOptions
    ? {
      onChange: handlePlainSelect,
      error: hasErrors,
      multiple: multiselect,
      options:
          multiselect || !required
            ? options
            : [
              {
                value: notSelected.value,
                text: localize(notSelected.text),
              },
              ...options,
            ],
      required,
      title,
      inline,
      width,
    }
    : {
      onChange: handleAsyncSelect,
      loadOptions: handleLoadOptions,
      valueComponent: multiselect
        ? createRemovableValueComponent(localize)
        : createValueComponent(localize),
      optionRenderer: createOptionComponent,
      inputProps: { type: 'react-select', name },
      className: hasErrors ? 'react-select--error' : '',
      multi: multiselect,
      backspaceRemoves: true,
      searchable: true,
      pagination: true,
      isLoading,
      onMenuScrollToBottom: handleLoadOptions,
      onInputChange: handleInputChange,
    }

  const className = `field${!hasOptions && required ? ' required' : ''}`

  return (
    <div
      className={className}
      style={{ opacity: `${disabled ? 0.25 : 1}` }}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={name}>{label}</label>}
      <Select
        {...ownProps}
        value={value}
        options={optionsState}
        onBlur={onBlur}
        name={name}
        placeholder={placeholder}
        disabled={disabled}
        openOnFocus
      />
      {hasErrors && (
        <Message title={label} list={errorKeys.map(localize)} compact={hasOptions} error />
      )}
    </div>
  )
}

InstitutionalSectorCodeField.propTypes = {
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

InstitutionalSectorCodeField.defaultProps = {
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
