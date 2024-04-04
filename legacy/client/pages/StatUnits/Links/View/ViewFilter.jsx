import React, { useState, useEffect, useCallback } from 'react'
import { func, shape, string, bool } from 'prop-types'
import { Icon, Form, Button, Popup } from 'semantic-ui-react'
import Select from 'react-select'
import debounce from 'lodash/debounce'

import { DateTimeField, RegionField } from '/components/fields'
import { getDate } from '/helpers/dateHelper'
import { statUnitTypes } from '/helpers/enums'
import { internalRequest } from '/helpers/request'
import { NameCodeOption, notSelected } from '/components/fields/RegionField'
import styles from './styles.scss'

const types = [['any', 'AnyType'], ...statUnitTypes]

function ViewFilter({ localize, isLoading, onFilter, value, locale }) {
  const [data, setData] = useState({
    wildcard: '',
    lastChangeFrom: '',
    lastChangeTo: '',
    dataSource: null,
    regionCode: null,
    type: 'any',
    extended: false,
  })

  const [dataSources, setDataSources] = useState([])
  const [regions, setRegions] = useState([])

  const loadDataSourceOptions = useCallback(() => {
    fetch('/api/lookup/paginated/7?page=0&pageSize=10', {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
    })
      .then(resp => resp.json())
      .then((result) => {
        const options =
          Array.isArray(result) && result.length > 0 ? result.map(NameCodeOption.transform) : []
        setDataSources(options)
      })
  }, [])

  useEffect(() => {
    loadDataSourceOptions()
  }, [loadDataSourceOptions])

  useEffect(() => {
    const {
      data: { dataSource, regionCode },
    } = data
    if (locale !== locale) {
      setData({
        ...data,
        dataSource: dataSource && NameCodeOption.transform(dataSource),
        regionCode: regionCode && NameCodeOption.transform(regionCode),
      })
    }
  }, [locale, data])

  const onFieldChanged = (e, { name, value }) => {
    setData(prevData => ({
      ...prevData,
      [name]: value,
    }))
  }

  const onSearchModeToggle = (e) => {
    e.preventDefault()
    setData(prevData => ({
      ...prevData,
      extended: !prevData.extended,
    }))
  }

  const handleSubmit = (e) => {
    e.preventDefault()
    const { dataSource, regionCode, type, ...filteredData } = data
    const updatedData = {
      ...filteredData,
      dataSource: dataSource && dataSource.value,
      regionCode: regionCode && regionCode.value,
      type: type !== 'any' ? Number(type) : undefined,
    }
    onFilter(updatedData)
  }

  const handleLoadOptions = useCallback(
    debounce((wildcard, page, callback) => {
      internalRequest({
        url: `/api/lookup/paginated/${12}`,
        queryParams: { page: page - 1, pageSize: 10, wildcard },
        method: 'get',
        onSuccess: (result) => {
          const regions =
            Array.isArray(result) && result.length > 0 ? result.map(NameCodeOption.transform) : []
          setRegions(prevRegions => prevRegions.concat(result))
          callback(null, { options: regions })
        },
      })
    }, 350),
    [],
  )

  const selectHandler = (selectedData, name) => {
    const value = selectedData ? NameCodeOption.transform(selectedData) : null
    setData(prevState => ({
      ...prevState,
      [name]: value,
    }))
  }

  const typeOptions = types.map(([value, text]) => ({
    value,
    text: localize(text),
  }))

  return (
    <Form onSubmit={handleSubmit} loading={isLoading}>
      <Form.Group widths="equal">
        <Form.Input
          name="wildcard"
          value={data.wildcard}
          onChange={onFieldChanged}
          label={localize('SearchWildcard')}
          placeholder={localize('Search')}
          size="large"
        />
        <Form.Select
          name="type"
          value={data.type}
          onChange={onFieldChanged}
          options={typeOptions}
          label={localize('StatisticalUnitType')}
          size="large"
          search
        />
      </Form.Group>
      {data.extended && (
        <div>
          <Form.Group widths="equal">
            <DateTimeField
              name="lastChangeFrom"
              value={data.lastChangeFrom}
              onChange={onFieldChanged}
              label="DateOfLastChangeFrom"
              localize={localize}
            />
            <Popup
              trigger={
                <div className={`field ${styles.items}`}>
                  <DateTimeField
                    name="lastChangeTo"
                    value={data.lastChangeTo}
                    onChange={onFieldChanged}
                    label="DateOfLastChangeTo"
                    localize={localize}
                    error={
                      getDate(data.lastChangeFrom) > getDate(data.lastChangeTo) &&
                      (data.lastChangeTo !== undefined || data.lastChangeTo !== '')
                    }
                  />
                </div>
              }
              content={`"${localize('DateOfLastChangeTo')}" ${localize('CantBeLessThan')} "${localize('DateOfLastChangeFrom')}"`}
              open={
                getDate(data.lastChangeFrom) > getDate(data.lastChangeTo) &&
                (data.lastChangeTo !== undefined || data.lastChangeTo !== '')
              }
            />
          </Form.Group>
          <label className={styles.label}>{localize('DataSource')}</label>
          <Select
            value={data.dataSource}
            options={dataSources}
            optionRenderer={NameCodeOption.render}
            onChange={selectedData => selectHandler(selectedData, 'dataSource')}
            openOnFocus
            placeholder={localize('DataSource')}
            inputProps={{ type: 'react-select' }}
          />
          <br />
          <label className={styles.label}>{localize('Region')}</label>
          <Select.Async
            value={data.regionCode}
            loadOptions={handleLoadOptions}
            options={regions}
            optionRenderer={NameCodeOption.render}
            onChange={selectedData => selectHandler(selectedData, 'regionCode')}
            pagination
            searchable
            openOnFocus
            placeholder={localize('Region')}
            inputProps={{ type: 'react-select' }}
          />
          <br />
        </div>
      )}
      <Button onClick={onSearchModeToggle} style={{ cursor: 'pointer' }}>
        <Icon name="search" />
        {localize(data.extended ? 'SearchDefault' : 'SearchExtended')}
      </Button>
      <Button color="blue" floated="right">
        {localize('Search')}
      </Button>
    </Form>
  )
}

ViewFilter.propTypes = {
  localize: func.isRequired,
  isLoading: bool,
  onFilter: func.isRequired,
  value: shape({
    name: string,
  }),
  locale: string.isRequired,
}

ViewFilter.defaultProps = {
  value: {
    name: '',
    extended: false,
  },
  isLoading: false,
}

export default ViewFilter
