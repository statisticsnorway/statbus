import React from 'react'
import { func, number, string, shape, bool } from 'prop-types'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'
import { equals } from 'ramda'

import { statUnitTypes } from 'helpers/enums'
import { internalRequest } from 'helpers/request'

export const defaultUnitSearchResult = {
  id: undefined,
  code: '',
  name: '',
  type: undefined,
}

const StatUnitView = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name.length > 50 ? (
      <span title={name}>{`${name.substring(0, 50)}...`}</span>
    ) : (
      <span>{name}</span>
    )}
  </span>
)

StatUnitView.propTypes = {
  'data-name': string.isRequired,
  'data-code': string.isRequired,
}

class UnitSearch extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    name: string.isRequired,
    onChange: func,
    value: shape({
      id: number,
      code: string,
      name: string,
      type: number,
    }),
    disabled: bool,
  }

  static defaultProps = {
    onChange: _ => _,
    value: defaultUnitSearchResult,
    disabled: false,
  }

  state = {
    isLoading: this.props.value.id > 0 && this.props.value.type > 0,
    codes: undefined,
  }

  componentDidMount() {
    const { id, type } = this.props.value
    if (id > 0 && type > 0) {
      internalRequest({
        url: `/api/statunits/getunitbyid/${type}/${id}`,
        onSuccess: (resp) => {
          const code = resp.properties.find(p => p.name === 'statId').value
          const name = resp.properties.find(p => p.name === 'name').value
          this.setState(
            {
              isLoading: false,
              codes: [
                {
                  'data-id': id,
                  'data-type': type,
                  'data-code': code,
                  'data-name': name,
                  title: id.toString(),
                },
              ],
            },
            () => {
              this.onChange({ id, code, name, type })
            },
          )
        },
        onFail: () => {
          this.setState({
            isLoading: false,
            codes: undefined,
          })
        },
      })
    }
  }

  shouldComponentUpdate(nextProps, nextState) {
    return !equals(this.props, nextProps) || !equals(this.state, nextState)
  }

  onCodeChange = (e, { value }) => {
    this.setState(
      {
        isLoading: value !== '',
      },
      () => {
        this.onChange({
          ...defaultUnitSearchResult,
          code: value,
        })
        if (value !== '') {
          this.searchData(value)
        }
      },
    )
  }

  onChange = (value) => {
    const { name, onChange } = this.props
    onChange(undefined, { name, value })
  }

  searchData = debounce(
    value =>
      internalRequest({
        url: '/api/StatUnits/SearchByStatId',
        method: 'get',
        queryParams: { code: value },
        onSuccess: (resp) => {
          const data = resp.find(v => v.code === this.props.value.code)
          this.setState(
            {
              isLoading: false,
              codes: resp.map(v => ({
                title: v.id.toString(),
                'data-name': v.name,
                'data-code': v.code,
                'data-id': v.id,
                'data-type': v.type,
              })),
            },
            () => {
              if (data) this.onChange(data)
            },
          )
        },
        onFail: () => {
          this.setState({
            isLoading: false,
          })
        },
      }),
    250,
  )

  codeSelectHandler = (e, { result }) => {
    const value = {
      id: result['data-id'],
      code: result['data-code'],
      name: result['data-name'],
      type: result['data-type'],
    }
    this.onChange(value)
  }

  render() {
    const { localize, name, value, disabled } = this.props
    const { isLoading, codes } = this.state
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
          onSearchChange={this.onCodeChange}
          value={value.code}
          onResultSelect={this.codeSelectHandler}
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
}

export default UnitSearch
