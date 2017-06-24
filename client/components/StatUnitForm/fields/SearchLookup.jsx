import React from 'react'

import SearchField from 'components/Search/SearchField'
import { internalRequest } from 'helpers/request'


const { func, shape, string, oneOfType, number } = React.PropTypes

class SearchLookup extends React.Component {

  static propTypes = {
    localize: func.isRequired,
    searchData: shape(),
    value: oneOfType([number, string]),
    name: string.isRequired,
    onChange: func.isRequired,
  }

  static defaultProps = {
    searchData: [],
    value: '',
    data: {},
    errors: [],
  }

  state = {
    data: {},
  }

  componentDidMount() {
    if (this.props.value) {
      internalRequest({
        url: `${this.props.searchData.editUrl}${this.props.value}`,
        method: 'get',
        onSuccess: (data) => {
          this.setState({ data })
        },
      })
    }
  }

  setLookupValue = (data) => {
    const { name } = this.props
    this.setState({ data }, () => this.props.onChange({ name, value: data.id }))
  }

  render() {
    const { searchData, localize } = this.props
    return (
      <SearchField
        localize={localize}
        searchData={{ ...searchData, data: this.state.data }}
        onValueSelected={this.setLookupValue}
        onValueChanged={() => {}}
      />
    )
  }
}

export default SearchLookup
