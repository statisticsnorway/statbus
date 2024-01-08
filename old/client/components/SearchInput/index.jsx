import React, { useState, useEffect, useCallback } from 'react'
import { func, shape, string, bool } from 'prop-types'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'
import { equals, isEmpty, isNil } from 'ramda'

import { internalRequest } from '/helpers/request'
import simpleName from './nameCreator.js'

const waitTime = 250

function SearchInput({
  localize,
  searchData: { url, editUrl, label, placeholder, data: initialData },
  onValueSelected,
  onValueChanged,
  required,
  disabled,
}) {
  const [data, setData] = useState(initialData)
  const [results, setResults] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [searchValue, setSearchValue] = useState('')

  useEffect(() => {
    if (!isEmpty(initialData) && !equals(data, initialData)) {
      setData(initialData)
    }
  }, [initialData])

  const handleSearchResultSelect = (e, { result: { data } }) => {
    e.preventDefault()
    setData({ ...data, name: simpleName(data) })
    onValueSelected(data)
  }

  const handleSearchChange = useCallback(
    (e, { value }) => {
      if (isNil(value) || isEmpty(value)) {
        return
      }
      setData(prevData => ({
        ...prevData,
        name: value,
      }))
      setSearchValue(value)
      onValueChanged(value)
      search(value)
    },
    [onValueChanged],
  )

  const search = debounce((params) => {
    internalRequest({
      url,
      queryParams: { wildcard: params },
      method: 'get',
      onSuccess: (result) => {
        setIsLoading(false)
        setResults(result.map(x => ({
          title: simpleName(x),
          description: x.code,
          data: x,
          key: x.code,
        })))
      },
      onFail: () => {
        setIsLoading(false)
        setResults([])
        onValueSelected({})
      },
    })
  }, waitTime)

  return (
    <Form.Input
      control={Search}
      onResultSelect={handleSearchResultSelect}
      onSearchChange={handleSearchChange}
      results={results}
      showNoResults={false}
      placeholder={localize(placeholder)}
      loading={isLoading}
      label={localize(label)}
      value={searchValue}
      disabled={disabled}
      fluid
      required={required}
      autoComplete="off"
    />
  )
}

SearchInput.propTypes = {
  localize: func.isRequired,
  searchData: shape({
    url: string.isRequired,
    editUrl: string,
    label: string.isRequired,
    placeholder: string.isRequired,
    data: shape({}).isRequired,
  }).isRequired,
  onValueSelected: func.isRequired,
  onValueChanged: func.isRequired,
  required: bool.isRequired,
  disabled: bool.isRequired,
}

export default SearchInput
