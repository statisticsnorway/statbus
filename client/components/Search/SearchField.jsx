import React from 'react'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'

import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'
import simpleName from './nameCreator'


const { func, shape, string, bool } = React.PropTypes
const waitTime = 250

class SearchField extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    searchData: shape({
      url: string.isRequired,
      label: string.isRequired,
      placeholder: string.isRequired,
      data: shape({}).isRequred,
    }).isRequired,
    onValueSelected: func.isRequired,
    isRequired: bool,
  }

  static defaultProps = {
    isRequired: false,
  }

  state = {
    data: this.props.searchData.data,
    results: [],
    isLoading: false,
  }

  handleSearchResultSelect = (e, { data }) => {
    e.preventDefault()
    this.setState({
      data: { ...data, name: simpleName(data) },
    })
    this.props.onValueSelected(data)
  }

  handleSearchChange = (e, value) => {
    this.setState(s => (
      {
        data: { ...s.data, name: value },
        isLoading: true,
      }
    ), () => {
      this.search(value)
    })
  }

  search = debounce(params => internalRequest({
    url: this.props.searchData.url,
    queryParams: { wildcard: params },
    method: 'get',
    onSuccess: (result) => {
      this.setState({
        isLoading: false,
        results: [...result.map(x => ({
          title: simpleName(x),
          description: x.code,
          data: x,
          key: x.code,
        }))],
      })
    },
    onFail: () => {
      this.setState({
        isLoading: false,
        results: [],
      },
        )
    },
  }), waitTime)

  render() {
    const { localize, searchData, isRequired } = this.props
    const { isLoading, results, data } = this.state

    return (
      <Form.Input
        control={Search}
        onResultSelect={this.handleSearchResultSelect}
        onSearchChange={this.handleSearchChange}
        results={results}
        showNoResults={false}
        placeholder={localize(searchData.placeholder)}
        loading={isLoading}
        label={localize(searchData.label)}
        value={data.name}
        fluid
        {...(isRequired ? { required: true } : {})}
      />
    )
  }
}

export default wrapper(SearchField)
