import React from 'react'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'

import { internalRequest } from 'helpers/request'
import { wrapper } from 'helpers/locale'

const { func, shape, string } = React.PropTypes
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
    callBack: func.isRequired,
  }


  state = {
    data: this.props.searchData.data,
    results: [],
    isLoading: false,
  }

  handleSearchResultSelect = (e, { data }) => {
    e.preventDefault()
    this.setState({
      data: { ...data, name: this.simplifyName(data) },
    })
    this.props.callBack(data)
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
    queryParams: { code: params },
    method: 'get',
    onSuccess: (result) => {
      this.setState({
        isLoading: false,
        results: [...result.map(x => ({
          title: this.simplifyName(x),
          description: x.code,
          data: x,
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

  simplifyName = data => (
    `${(data.adminstrativeCenter === null || data.adminstrativeCenter === undefined)
      ? data.name
      : `${data.adminstrativeCenter}, `}${data.name}`
      )

  render() {
    const { localize, searchData } = this.props
    const { isLoading, results, data } = this.state

    return (
      <Form.Field
        value={data.name}
        label={localize(searchData.label)}
        placeholder={localize(searchData.placeholder)} control={Search}
        loading={isLoading} fluid
        onResultSelect={this.handleSearchResultSelect}
        onSearchChange={this.handleSearchChange} results={results}
        showNoResults={false}
        required
      />
    )
  }
}

export default wrapper(SearchField)
