import React, { useState, useEffect } from 'react'
import { arrayOf, func, string, oneOfType, number, bool } from 'prop-types'
import { Message } from 'semantic-ui-react'
import { isEmpty } from 'ramda'
import SearchInput from '/components/SearchInput'
import sources from '/components/SearchInput/sources'
import { internalRequest } from '/helpers/request'

const getSearchData = (name) => {
  switch (name) {
    case 'instSectorCodeId':
      return sources.sectorCode
    case 'legalFormId':
      return sources.legalForm
    case 'parentOrgLink':
      return sources.parentOrgLink
    case 'reorgReferences':
      return sources.reorgReferences
    default:
      throw new Error(`SearchField couldn't find search source for the given name: "${name}"`)
  }
}

export const SearchField = ({
  name,
  value: initialValue,
  errors: errorKeys,
  disabled,
  onChange,
  localize,
  required,
  popuplocalizedKey,
}) => {
  const [value, setValue] = useState({})
  const searchData = { ...getSearchData(name), value }

  useEffect(() => {
    const { editUrl } = getSearchData(name)
    if (initialValue) {
      internalRequest({
        url: `${editUrl}${initialValue}`,
        method: 'get',
        onSuccess: data => setValue(data),
      })
    }
  }, [name, initialValue])

  useEffect(() => {
    if (isEmpty(initialValue)) {
      setValue('')
    }
  }, [initialValue])

  const setLookupValue = (data) => {
    setValue(data.name)
    onChange(undefined, { name, value: data.id })
  }

  const handleChange = (data) => {
    setValue(typeof data !== 'object' ? data : data.name)
  }

  const hasErrors = errorKeys.length > 0

  return (
    <div
      className={`ui field ${hasErrors ? 'error' : ''}`}
      data-tooltip={popuplocalizedKey ? localize(popuplocalizedKey) : null}
      data-position="top left"
    >
      <SearchInput
        searchData={searchData}
        onValueChanged={handleChange}
        onValueSelected={setLookupValue}
        disabled={disabled}
        localize={localize}
        required={required}
      />
      {hasErrors && (
        <Message title={localize(searchData.label)} content={errorKeys.map(localize)} error />
      )}
    </div>
  )
}

SearchField.propTypes = {
  name: string.isRequired,
  value: oneOfType([number, string]),
  errors: arrayOf(string),
  disabled: bool,
  onChange: func.isRequired,
  localize: func.isRequired,
  required: bool.isRequired,
  popuplocalizedKey: string,
}

SearchField.defaultProps = {
  value: '',
  errors: [],
  disabled: false,
  popuplocalizedKey: null,
}
