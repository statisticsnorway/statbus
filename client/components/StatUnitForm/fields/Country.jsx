import React from 'react'
import { Table, Form, Search } from 'semantic-ui-react'

import debounce from 'lodash/debounce'
import { internalRequest } from 'helpers/request'

const { shape, number, func, string, oneOfType } = React.PropTypes

const CountryCode = ({ 'data-name': name, 'data-code': code }) => (
  <span>
    <strong>{code}</strong>
    &nbsp;
    {name.length > 50
      ? <span title={name}>{`${name.substring(0, 50)}...`}</span>
      : <span>{name}</span>
    }
  </span>
)

CountryCode.propTypes = {
  'data-name': string.isRequired,
  'data-code': string.isRequired,
}

class Country extends React.Component {
  static propTypes = {
    data: shape({
      id: number,
      activityRevy: oneOfType([string, number]),
      activityRevxCategory: shape({
        code: string.isRequired,
        name: string.isRequired,
      }),
    }).isRequired,
    localize: func.isRequired,
  }

  state = {
    data: this.props.data,
    isLoading: false,
    codes: [],
    isOpen: false,
  }

  onFieldChange = (e, { name, value }) => {
    this.setState(s => ({
      data: { ...s.data, [name]: value },
    }))
  }

  onCodeChange = (e, value) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: {
          id: undefined,
          code: value,
          name: '',
        },
      },
      isLoading: true,
    }))
    this.searchData(value)
  }

  searchData = debounce(value => internalRequest({
    url: '/api/activities/search',
    method: 'get',
    queryParams: { code: value },
    onSuccess: (resp) => {
      this.setState(s => ({
        data: {
          ...s.data,
          activityRevxCategory: resp.find(v => v.code === s.data.activityRevxCategory.code)
            || s.data.activityRevxCategory,
        },
        isLoading: false,
        codes: resp.map(v => ({ title: v.id.toString(), 'data-name': v.name, 'data-code': v.code, 'data-id': v.id })),
      }))
    },
    onFail: () => {
      this.setState({
        isLoading: false,
      })
    },
  }), 250)

  codeSelectHandler = (e, result) => {
    this.setState(s => ({
      data: {
        ...s.data,
        activityRevxCategory: {
          id: result['data-id'],
          code: result['data-code'],
          name: result['data-name'],
        },
      },
    }))
  }

  handleOpen = () => {
    this.setState({ isOpen: true })
  }

  render() {
    const { data, isLoading, codes } = this.state
    const { localize } = this.props
    return (
      <Table.Row>
        <Table.Cell colSpan={8}>
          <Form as="div">
            <Form.Group widths="equal">
              <Form.Field
                label={localize('StatUnitActivityRevX')}
                control={Search}
                loading={isLoading}
                placeholder={localize('StatUnitActivityRevX')}
                onResultSelect={this.codeSelectHandler}
                onSearchChange={this.onCodeChange}
                results={codes}
                resultRenderer={CountryCode}
                value={data.activityRevxCategory.code}
                error={!data.activityRevxCategory.code}
                required
                showNoResults={false}
                fluid
              />
              <Form.Input
                label={localize('Country')}
                value={data.activityRevxCategory.name}
                readOnly
              />
            </Form.Group>
          </Form>
        </Table.Cell>
      </Table.Row>
    )
  }
}

export default Country
