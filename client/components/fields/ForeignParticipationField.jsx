import React, { useState, useEffect, useCallback } from 'react'
import { arrayOf, string, number, oneOfType, func, bool, shape } from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import * as R from 'ramda'

import { hasValue, createPropType } from '../../helpers/validation'
import { internalRequest } from '../../helpers/request'
import { getNewName } from '../../helpers/locale'

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

export function ForeignParticipationField({
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
  locale,
  popuplocalizedKey,
  pageSize,
  waitTime,
  lookup,
  responseToOption,
  options: initialOptions,
}) {
  const [value, setValue] = useState(hasValue(initialValue) ? initialValue : multiselect ? [] : notSelected.value)
  const [options, setOptions] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const loadOptions = useCallback(() => {
    if (!isLoading) {
      const queryParams = { page, pageSize, wildcard }

      internalRequest({
        url: `/api/lookup/paginated/${lookup}`,
        queryParams,
        method: 'get',
        onSuccess: (data) => {
          let newOptions = [...data]

          if (responseToOption) newOptions = newOptions.map(responseToOption)

          setOptions(prevOptions => prevOptions.concat(newOptions))
          setPage(prevPage => prevPage + 1)
          setIsLoading(false)
        },
      })
    }
  }, [isLoading, lookup, page, pageSize, responseToOption, wildcard])

  const handleLoadOptions = debounce(loadOptions, waitTime)

  const handleAsyncSelect = useCallback(
    (data) => {
      const raw = data !== null ? data : { value: notSelected.value }
      const newValue = multiselect ? raw.map(x => x.value) : raw.value

      if (!R.equals(value, newValue)) {
        setValue(newValue)
        onChange(undefined, { ...this.props, value: newValue }, data)
      }
    },
    [multiselect, onChange, value],
  )

  const handlePlainSelect = useCallback(
    (event, { value: newValue, ...data }) => {
      if (!R.equals(value, newValue)) {
        setValue(newValue)
        onChange(event, { ...data, value: newValue })
      }
    },
    [onChange, value],
  )

  const handleInputChange = useCallback(
    (newValue) => {
      if (newValue && lookup !== null) {
        setIsLoading(true)

        const queryParams = { page: 0, pageSize, wildcard: newValue }

        internalRequest({
          url: `/api/lookup/paginated/${lookup}`,
          queryParams,
          method: 'get',
          onSuccess: (data) => {
            let newOptions = [...data]

            if (responseToOption) newOptions = newOptions.map(responseToOption)

            setOptions(newOptions)
            setPage(0)
            setIsLoading(false)
          },
        })
      }
    },
    [lookup, pageSize, responseToOption],
  )

  useEffect(() => {
    if (hasValue(initialOptions)) return
    const { value: ids, lookup, multiselect, responseToOption } = this.props
    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids },
      method: 'get',
      onSuccess: (value) => {
        if (hasValue(value)) {
          setValue(multiselect ? value.map(responseToOption) : responseToOption(value[0]))
          multiselect ? value.map(responseToOption) : responseToOption(value[0])
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
        setOptions(newOptions)
        setIsLoading(false)
        setPage(prevPage => prevPage + 1)
      })
  }, [hasValue, initialValue, initialOptions, multiselect, props, responseToOption])

  useEffect(() => {
    const { value, initialValue } = this.state
    const { locale, multiselect, responseToOption } = this.props
    const ids =
      props.isEdit && R.is(Array, value)
        ? R.is(Array, initialValue) && initialValue.map(x => x.id)
        : initialValue && initialValue.id

    if (props.isEdit && R.equals(ids, value)) {
      setValue(initialValue)
    }

    if (!R.equals(props.value && value)) {
      setValue(props.value)
    }

    if (props.value === 0 || props.value.length === 0 || props.value[0] === 0) {
      setValue('')
    }

    if (props.locale !== locale) {
      setValue(multiselect ? value.map(responseToOption) : responseToOption(value))
      setOptions(prevOptions => prevOptions.map(responseToOption))
    }
  }, [props])

  useEffect(() => {
    handleLoadOptions.cancel()
  }, [])

  return (
    <div
      className={`field${!hasOptions && required ? ' required' : ''}`}
      style={{ opacity: `${disabled ? 0.25 : 1}` }}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={name}>{label}</label>}
      <SemanticUiSelect
        onChange={handlePlainSelect}
        error={hasErrors}
        multiple={multiselect}
        options={
          multiselect || !required
            ? options
            : [
                {
                  value: notSelected.value,
                  text: localize(notSelected.text),
                },
                ...options,
              ]
        }
        required={required}
        title={title}
        inline={inline}
        width={width}
        value={value}
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

ForeignParticipationField.propTypes = {
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

ForeignParticipationField.defaultProps = {
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
