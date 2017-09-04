import React from 'react'
import { func, shape, string, bool } from 'prop-types'
import { Form, Search } from 'semantic-ui-react'
import debounce from 'lodash/debounce'
import R from 'ramda'
import Select from 'react-select'

import { internalRequest } from 'helpers/request'
import simpleName from './nameCreator'

const waitTime = 250

class SearchInput extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    searchData: shape({
      url: string.isRequired,
      editUrl: string,
      label: string.isRequired,
      placeholder: string.isRequired,
      data: shape({}).isRequred,
    }).isRequired,
    onValueSelected: func.isRequired,
    onValueChanged: func.isRequired,
    isRequired: bool,
    disabled: bool,
  }

  static defaultProps = {
    isRequired: false,
    disabled: false,
  }

  state = {
    data: this.props.searchData.data,
    results: [],
    isLoading: false,
    isSelected: false,
    value: [],
  }

  componentWillReceiveProps(newProps) {
    const newData = newProps.searchData.data
    if (!R.isEmpty(newData) && !R.equals(this.state.data, newData)) {
      this.setState({ data: newData })
    }
  }

  // onChange = (value) => {
  //   this.setState({ value: value })
  // }

  handleSearchResultSelect = (e, { result: { data } }) => {
    e.preventDefault()
    this.setState({
      data: { ...data, name: simpleName(data) },
    }, () => this.props.onValueSelected(data))
  }

  handleSearchChange = (e, { value }) => {
    this.setState(s => (
      {
        data: { ...s.data, name: value },
        isLoading: true,
      }
    ), () => {
      this.props.onValueChanged(value)
      this.search(value)
    })
  }

  // getOptions = (input, page, callback) => {
  //   internalRequest({
  //     url: `/api/lookup/paginated/1?page=${page}&pageSize=10&wildcard=${input}`,
  //     method: 'get',
  //     onSuccess: (value) => {
  //       console.log('getOptions', input, page, value)
  //       callback(null, { options: value.map(x => ({ value: x.id, name: x.name })) })
  //     },
  //   })
  // }

  search = (input, pageNumber, callback) => {
    debounce(() => {
      internalRequest({
        url: '/api/lookup/paginated/1', // this.props.searchData.url,
        queryParams: { page: pageNumber - 1, pageSize: 10, wildcard: input },
        method: 'get',
        onSuccess: (result) => {
          this.setState({
            isLoading: false,
            results: [...result.map(x => ({
              name: simpleName(x),
              description: x.code,
              data: x,
              value: x.code,
            }))],
          })
          callback(null, { options: result.map(x => ({ value: x.id, name: x.name })) })
        },
        onFail: () => {
          this.setState({
            isLoading: false,
            results: [],
          }, () => {
            this.props.onValueSelected({})
          })
        },
      })
    }, waitTime)
  }

  // search = debounce((params) => {
  //   internalRequest({
  //     url: this.props.searchData.url,
  //     queryParams: { wildcard: params },
  //     method: 'get',
  //     onSuccess: (result) => {
  //       this.setState({
  //         isLoading: false,
  //         results: [...result.map(x => ({
  //           title: simpleName(x),
  //           description: x.code,
  //           data: x,
  //           key: x.code,
  //         }))],
  //       })
  //     },
  //     onFail: () => {
  //       this.setState({
  //         isLoading: false,
  //         results: [],
  //       }, () => {
  //         this.props.onValueSelected({})
  //       })
  //     },
  //   })
  // }, waitTime)

  render() {
    const { localize, searchData, isRequired, disabled } = this.props
    const { isLoading, results, data } = this.state
    return (
      <Form.Input
        control={Select.Async}
        placeholder={localize(searchData.placeholder)}
        label={localize(searchData.label)}
        value={data.name}
        fluid

        name="form-field-name"
        loadOptions={this.search}
        labelKey="name"
        valueKey="value"
        onChange={this.handleSearchChange}
        pagination
        multi
        backspaceRemoves

        {...(isRequired ? { required: true } : {})}
      />
    )
  }


}

export default SearchInput
