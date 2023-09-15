import React, { useState, useEffect, useCallback } from 'react'
import PropTypes from 'prop-types'
import { Message, Select as SemanticUiSelect, Label } from 'semantic-ui-react'
import ReactSelect from 'react-select'
import debounce from 'lodash/debounce'
import R from 'ramda'

import { hasValue, createPropType } from 'helpers/validation'
import { internalRequest } from 'helpers/request'
import { getNewName } from 'helpers/locale'

import styles from './styles.pcss'

export const notSelected = { value: undefined, text: 'NotSelected' }

export const NameCodeOption = {
  transform: x => ({
    ...x,
    value: x.id,
    label: getNewName(x),
  }),
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

const createRemovableValueComponent = localize => ({ value, onRemove }) => (
  <Label
    content={value.value === notSelected.value ? localize(value.label) : value.label}
    onRemove={() => onRemove(value)}
    removeIcon="delete"
    color="blue"
    basic
  />
)

const createValueComponent = localize => ({ value: { value, label } }) => (
  <div className="Select-value">
    <span className="Select-value-label" role="option" aria-selected="true">
      {value === notSelected.value ? localize(notSelected.text) : label}
    </span>
  </div>
)

const numOrStr = PropTypes.oneOfType([PropTypes.number, PropTypes.string])

const RegionField = ({
  name,
  value: initialValue,
  onChange,
  onBlur,
  errors,
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
}) => {
  const label = labelKey !== undefined ? localize(labelKey) : undefined
  const title = titleKey ? localize(titleKey) : label
  const placeholder = placeholderKey ? localize(placeholderKey) : label

  const [value, setValue] = useState(hasValue(initialValue) ? initialValue : multiselect ? [] : notSelected.value)
  const [options, setOptions] = useState([])
  const [optionsFetched, setOptionsFetched] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [page, setPage] = useState(0)
  const [wildcard, setWildcard] = useState('')

  const loadOptions = useCallback(
    debounce(() => {
      if (!isLoading) {
        internalRequest({
          url: `/api/lookup/paginated/${lookup}`,
          queryParams: { page, pageSize, wildcard },
          method: 'get',
          onSuccess: (data) => {
            let newOptions = [...data]

            if (responseToOption) {
              newOptions = newOptions.map(responseToOption)
            }
            setOptions(prevOptions => [...prevOptions, ...newOptions])
            setPage(page + 1)
          },
        })
      }
    }, waitTime),
    [isLoading, lookup, pageSize, wildcard, responseToOption, page, waitTime],
  )

  const handleAsyncSelect = (data) => {
    const raw = data !== null ? data : { value: notSelected.value }
    const selectedValue = multiselect ? raw.map(x => x.value) : raw.value
    setValue(selectedValue)
    onChange(undefined, { ...selectedValue })
  }

  const handlePlainSelect = (event, { value: selectedValue, ...data }) => {
    const nextData = { ...data, ...selectedValue }
    setValue(selectedValue)
    onChange(event, nextData)
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

          if (responseToOption) {
            newOptions = newOptions.map(responseToOption)
          }
          setOptions(newOptions)
          setPage(0)
          setIsLoading(false)
        },
      })
    }
  }

  useEffect(() => {
    if (hasValue(initialOptions)) return

    setIsLoading(true)

    internalRequest({
      url: `/api/lookup/${lookup}/GetById/`,
      queryParams: { ids: initialValue },
      method: 'get',
      onSuccess: (valueData) => {
        if (hasValue(valueData)) {
          setValue(multiselect ? valueData.map(responseToOption) : responseToOption(valueData[0]))
          setIsLoading(false)
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
        setPage(1)
      })
  }, [initialOptions, initialValue, multiselect, lookup, responseToOption, pageSize])

  useEffect(() => {
    const ids = R.is(Array, initialValue)
      ? R.is(Array, initialValue) && initialValue.map(x => x.id)
      : initialValue && initialValue.id
    if (isEdit && R.equals(ids, value)) {
      setValue(initialValue)
    }
    if (!R.equals(initialValue && value)) {
      setValue(initialValue)
    }
    if (initialValue === 0 || initialValue.length === 0 || initialValue[0] === 0) {
      setValue('')
    }
    if (locale !== locale) {
      setValue(multiselect ? value.map(responseToOption) : responseToOption(value))
      setOptions(options.map(responseToOption))
    }
  }, [locale, multiselect, responseToOption, isEdit, initialValue, value, options])

  useEffect(() => () => {
    handleLoadOptions.cancel()
  }, [handleLoadOptions])

  return (
    <div
      className={`field${!hasValue(options) && required ? ' required' : ''}`}
      style={{ opacity: `${disabled ? 0.25 : 1}` }}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      {label !== undefined && <label htmlFor={name}>{label}</label>}
      {hasValue(options) ? (
        <SemanticUiSelect
          onChange={handlePlainSelect}
          error={touched && hasValue(errors)}
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
          onBlur={onBlur}
          name={name}
          placeholder={placeholder}
          disabled={disabled}
          openOnFocus
          value={value}
        />
      ) : (
        <ReactSelect
          onChange={handleAsyncSelect}
          loadOptions={loadOptions}
          valueComponent={
            multiselect ? createRemovableValueComponent(localize) : createValueComponent(localize)
          }
          optionRenderer={createOptionComponent}
          inputProps={{ type: 'react-select', name }}
          className={touched && hasValue(errors) ? 'react-select--error' : ''}
          multi={multiselect}
          backspaceRemoves
          searchable
          pagination
          isLoading={isLoading}
          onMenuScrollToBottom={loadOptions}
          onInputChange={handleInputChange}
          name={name}
          placeholder={placeholder}
          onBlur={onBlur}
          value={value}
        />
      )}
      {touched && hasValue(errors) && (
        <Message title={label} list={errors.map(localize)} compact={hasValue(options)} error />
      )}
    </div>
  )
}

RegionField.propTypes = {
  name: PropTypes.string.isRequired,
  value: createPropType(props => (props.multiselect ? PropTypes.arrayOf(numOrStr) : numOrStr)),
  onChange: PropTypes.func.isRequired,
  onBlur: PropTypes.func,
  errors: PropTypes.arrayOf(PropTypes.string),
  label: PropTypes.string,
  title: PropTypes.string,
  placeholder: PropTypes.string,
  multiselect: PropTypes.bool,
  required: PropTypes.bool,
  touched: PropTypes.bool,
  disabled: PropTypes.bool,
  inline: PropTypes.bool,
  width: numOrStr,
  createOptionComponent: PropTypes.func,
  localize: PropTypes.func.isRequired,
  locale: PropTypes.string.isRequired,
  popuplocalizedKey: PropTypes.string,
  pageSize: PropTypes.number,
  waitTime: PropTypes.number,
  lookup: PropTypes.number,
  responseToOption: PropTypes.func,
  options: PropTypes.arrayOf(PropTypes.shape({
    value: numOrStr.isRequired,
    text: numOrStr.isRequired,
  })),
}

RegionField.defaultProps = {
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

export default RegionField
