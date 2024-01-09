import React, { useState, useEffect, useCallback } from 'react'
import { func, number, string, shape, bool } from 'prop-types'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'
import * as R from 'ramda'

import { statUnitTypes } from '/helpers/enums'
import { internalRequest } from '/helpers/request'

export const defaultUnitSearchResult = {
  id: undefined,
  code: '',
  name: '',
  type: undefined,
  regId: undefined,
}

const StatUnitView = ({ 'data-name': name, 'data-code': code, 'data-type': type, localize }) => (
  <span>
    <strong>
      {code} - {localize && localize(statUnitTypes.get(type))}
    </strong>
    <br />
    {name && name.length > 50 ? (
      <span title={name}>{`${name.substring(0, 50)}...`}</span>
    ) : (
      <span>{name}</span>
    )}
  </span>
)

StatUnitView.propTypes = {
  'data-name': string.isRequired,
  'data-code': string.isRequired,
  'data-type': string.isRequired,
  localize: func.isRequired,
}

function UnitSearch({ localize, name, onChange, value, disabled, type, isDeleted }) {
  const [isLoading, setIsLoading] = useState(value.id > 0 && value.type > 0)
  const [codes, setCodes] = useState(undefined)

  useEffect(() => {
    const { id, type } = value
    if (id > 0 && type > 0) {
      internalRequest({
        url: `/api/statunits/getunitbyid/${type}/${id}`,
        onSuccess: (resp) => {
          const code = resp.properties.find(p => p.name === 'statId').value
          const name = resp.properties.find(p => p.name === 'name').value
          setCodes([
            {
              'data-id': id,
              'data-type': type,
              'data-code': code,
              'data-name': name,
              title: id.toString(),
              localize,
            },
          ])
          onChange({
            id,
            code,
            name,
            type,
          })
          setIsLoading(false)
        },
        onFail: () => {
          setIsLoading(false)
          setCodes(undefined)
        },
      })
    }
  }, [value, localize, onChange])

  useEffect(() => {
    setIsLoading(value.id > 0 && value.type > 0)
  }, [value])

  const onCodeChange = (e, { value }) => {
    setIsLoading(value !== '')
    onChange({
      ...defaultUnitSearchResult,
      code: value,
    })
    if (value !== '') {
      searchData(type, value, isDeleted)
    }
  }

  const searchData = useCallback(
    debounce(
      (type, value, isDeleted) =>
        internalRequest({
          url: '/api/StatUnits/SearchByStatId',
          method: 'get',
          queryParams:
            name === 'source2'
              ? { type, code: value, regId: value.regId, isDeleted }
              : { type, code: value, isDeleted },
          onSuccess: (resp) => {
            const data = resp.find(v => v.code === value.code)
            setCodes(resp.map(v => ({
              title: v.id.toString(),
              'data-name': v.name,
              'data-code': v.code,
              'data-id': v.id,
              'data-type': v.type,
              localize,
            })))
            if (data) onChange(data)
            setIsLoading(false)
          },
          onFail: () => {
            setIsLoading(false)
          },
        }),
      250,
    ),
    [localize, onChange, name, type, isDeleted],
  )

  const codeSelectHandler = (e, { result }) => {
    const newValue = {
      id: result['data-id'],
      code: result['data-code'],
      name: result['data-name'],
      type: result['data-type'],
    }
    onChange(newValue)
  }

  const unitType = statUnitTypes.get(value.type)

  return (
    <Form.Group>
      <Form.Field
        as={Search}
        name={name}
        loading={isLoading}
        placeholder={localize('StatId')}
        results={codes}
        required
        showNoResults={false}
        fluid
        onSearchChange={onCodeChange}
        value={value.code}
        onResultSelect={codeSelectHandler}
        resultRenderer={StatUnitView}
        disabled={disabled}
        width={3}
      />
      <Form.Input
        value={value.name}
        disabled={disabled}
        width={10}
        placeholder={localize('Name')}
        readOnly
      />
      <Form.Input
        value={unitType !== undefined ? localize(unitType) : ''}
        disabled={disabled}
        width={3}
        placeholder={localize('UnitType')}
        readOnly
      />
    </Form.Group>
  )
}

UnitSearch.propTypes = {
  localize: func.isRequired,
  name: string.isRequired,
  onChange: func,
  value: shape({
    id: number,
    code: string,
    name: string,
    type: number,
    regId: number,
  }),
  disabled: bool,
  type: number,
  isDeleted: bool,
}

export default UnitSearch
